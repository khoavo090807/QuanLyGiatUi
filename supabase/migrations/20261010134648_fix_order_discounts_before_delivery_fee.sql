BEGIN;

-- Reserve the promotion before redeeming points. Points can cover the full
-- discounted order total, including quoted delivery fees.
CREATE OR REPLACE FUNCTION public.submit_laundry_booking_request(
  p_items jsonb,
  p_hinhthucnhando text,
  p_diachinhan text,
  p_ngayhen date,
  p_giohen time without time zone,
  p_ghichu text,
  p_idempotency_key uuid,
  p_use_points boolean,
  p_makhuyenmai text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_result jsonb;
  booking_id bigint;
BEGIN
  IF p_items IS NULL THEN
    booking_result := public.submit_laundry_booking_without_details(
      p_hinhthucnhando,
      p_diachinhan,
      p_ngayhen,
      p_giohen,
      p_ghichu,
      p_idempotency_key
    );
  ELSE
    -- Create the booking and service lines first, but defer point redemption.
    booking_result := public.submit_laundry_order_cart(
      p_items,
      p_hinhthucnhando,
      p_diachinhan,
      p_ngayhen,
      p_giohen,
      p_ghichu,
      p_idempotency_key
    );
  END IF;

  booking_id := (booking_result->>'bookingid')::bigint;

  IF nullif(btrim(p_makhuyenmai), '') IS NOT NULL THEN
    PERFORM public.set_booking_promotion(booking_id, p_makhuyenmai);
  END IF;

  IF p_items IS NOT NULL AND coalesce(p_use_points, false) THEN
    -- This RPC finds the already-created booking by idempotency key and now
    -- sees the reserved promotion when calculating redeemable points.
    booking_result := public.submit_laundry_order_cart_with_points(
      p_items,
      p_hinhthucnhando,
      p_diachinhan,
      p_ngayhen,
      p_giohen,
      p_ghichu,
      p_idempotency_key,
      true
    );
  END IF;

  RETURN booking_result;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_laundry_booking_request(
  jsonb, text, text, date, time without time zone, text, uuid, boolean, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_request(
  jsonb, text, text, date, time without time zone, text, uuid, boolean, text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_laundry_order_cart_with_points(
  p_items jsonb,
  p_hinhthucnhando text,
  p_diachinhan text,
  p_ngayhen date,
  p_giohen time without time zone,
  p_ghichu text,
  p_idempotency_key uuid,
  p_use_points boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_id bigint := (SELECT private.current_customer_id());
  booking_result jsonb;
  booking_id bigint;
  booking_row public."Booking"%ROWTYPE;
  promotion public."KhuyenMai"%ROWTYPE;
  available_points integer := 0;
  points_to_use integer := 0;
  points_discount numeric(18,2) := 0;
  promotion_discount numeric(18,2) := 0;
  total_amount numeric(18,2) := 0;
  total_delivery_fee numeric(12,2) := 0;
  remaining_points integer := 0;
BEGIN
  IF customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  booking_result := public.submit_laundry_order_cart(
    p_items,
    p_hinhthucnhando,
    p_diachinhan,
    p_ngayhen,
    p_giohen,
    p_ghichu,
    p_idempotency_key
  );
  booking_id := (booking_result->>'bookingid')::bigint;

  SELECT *
  INTO booking_row
  FROM public."Booking"
  WHERE "BookingID" = booking_id
    AND "KhachHangID" = customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  SELECT COALESCE(SUM("ThanhTien"), 0)
  INTO total_amount
  FROM public."ChiTietBooking"
  WHERE "BookingID" = booking_id;

  total_delivery_fee := coalesce(booking_row."PickupDeliveryFee", 0)
    + coalesce(booking_row."DeliveryFee", 0);

  IF booking_row."KhuyenMaiID" IS NOT NULL THEN
    SELECT *
    INTO promotion
    FROM public."KhuyenMai"
    WHERE "KhuyenMaiID" = booking_row."KhuyenMaiID";

    IF FOUND
       AND promotion."TrangThai" = 'Hoạt động'
       AND promotion."NgayBatDau" <= current_date
       AND promotion."NgayKetThuc" >= current_date
       AND (
         promotion."GiaTriDonToiThieu" IS NULL
         OR total_amount >= promotion."GiaTriDonToiThieu"
       ) THEN
      promotion_discount := CASE
        WHEN promotion."LoaiKhuyenMai" = 'Phần trăm'
          THEN total_amount * promotion."GiaTriGiam" / 100
        ELSE promotion."GiaTriGiam"
      END;
      IF promotion."MucGiamToiDa" IS NOT NULL THEN
        promotion_discount := least(
          promotion_discount,
          promotion."MucGiamToiDa"
        );
      END IF;
      promotion_discount := greatest(
        least(promotion_discount, total_amount),
        0
      );
    END IF;
  END IF;

  IF NOT booking_row."DiemDaTru" THEN
    IF coalesce(p_use_points, false) THEN
      SELECT "DiemHienTai"
      INTO available_points
      FROM public."DiemTichLuy"
      WHERE "KhachHangID" = customer_id
      FOR UPDATE;

      IF FOUND THEN
        points_to_use := least(
          available_points::numeric,
          floor(greatest(
            total_amount - promotion_discount + total_delivery_fee,
            0
          ))
        )::integer;
        points_discount := points_to_use;

        IF points_to_use > 0 THEN
          UPDATE public."DiemTichLuy"
          SET
            "DiemHienTai" = "DiemHienTai" - points_to_use,
            "NgayCapNhat" = now()
          WHERE "KhachHangID" = customer_id;
        END IF;
      END IF;
    END IF;

    UPDATE public."Booking"
    SET
      "DiemSuDung" = points_to_use,
      "TienGiamDoDiem" = points_discount,
      "DiemDaTru" = true
    WHERE "BookingID" = booking_id;
  ELSE
    points_to_use := booking_row."DiemSuDung";
    points_discount := booking_row."TienGiamDoDiem";
  END IF;

  SELECT COALESCE("DiemHienTai", 0)
  INTO remaining_points
  FROM public."DiemTichLuy"
  WHERE "KhachHangID" = customer_id;
  remaining_points := COALESCE(remaining_points, 0);

  RETURN booking_result || jsonb_build_object(
    'thanhtien', total_amount,
    'diemsudung', points_to_use,
    'tiengiamdodiem', points_discount,
    'tiengiamkhuyenmai', promotion_discount,
    'thanhtoan', greatest(
      total_amount + total_delivery_fee
        - points_discount - promotion_discount,
      0
    ),
    'diemconlai', remaining_points
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_laundry_booking_with_delivery(
  p_items jsonb,
  p_hinhthucnhando text,
  p_hinhthucgiaodo text,
  p_diachinhan text,
  p_ngayhen date,
  p_giohen time without time zone,
  p_ghichu text,
  p_idempotency_key uuid,
  p_use_points boolean,
  p_phuongthucthanhtoan text,
  p_makhuyenmai text DEFAULT NULL,
  p_diachigiao text DEFAULT NULL,
  p_delivery_fee_quote_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_result jsonb;
  customer_id bigint := (SELECT private.current_customer_id());
  current_user_id uuid := (SELECT auth.uid());
  booking_id bigint;
  quote_row public.delivery_fee_quotes%ROWTYPE;
  pickup_distance integer := 0;
  delivery_distance integer := 0;
  pickup_fee numeric(12, 2) := 0;
  delivery_fee numeric(12, 2) := 0;
  total_delivery_fee numeric(12, 2) := 0;
  pickup_address text;
  delivery_address text;
BEGIN
  IF current_user_id IS NULL OR customer_id IS NULL THEN
    RAISE EXCEPTION 'An active customer account is required';
  END IF;
  IF p_hinhthucnhando NOT IN ('Tại cửa hàng', 'Tại nhà')
     OR p_hinhthucgiaodo NOT IN ('Tại cửa hàng', 'Tại nhà') THEN
    RAISE EXCEPTION 'Unsupported delivery method';
  END IF;
  IF p_hinhthucnhando = 'Tại nhà'
     AND nullif(btrim(COALESCE(p_diachinhan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Pickup address is required';
  END IF;
  IF p_hinhthucgiaodo = 'Tại nhà'
     AND nullif(btrim(COALESCE(p_diachigiao, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Delivery address is required';
  END IF;

  pickup_address := CASE WHEN p_hinhthucnhando = 'Tại nhà'
    THEN nullif(btrim(p_diachinhan), '') ELSE NULL END;
  delivery_address := CASE WHEN p_hinhthucgiaodo = 'Tại nhà'
    THEN nullif(btrim(p_diachigiao), '') ELSE NULL END;

  IF pickup_address IS NOT NULL OR delivery_address IS NOT NULL THEN
    IF p_delivery_fee_quote_id IS NULL THEN
      RAISE EXCEPTION 'A current delivery fee quote is required';
    END IF;

    SELECT * INTO quote_row
    FROM public.delivery_fee_quotes
    WHERE id = p_delivery_fee_quote_id
    FOR UPDATE;

    IF NOT FOUND
       OR quote_row.auth_user_id <> current_user_id
       OR (
         pickup_address IS NULL
         AND quote_row.pickup_address_hash IS NOT NULL
       )
       OR (
         pickup_address IS NOT NULL
         AND quote_row.pickup_address_hash IS DISTINCT FROM
           encode(extensions.digest(convert_to(btrim(pickup_address), 'UTF8'), 'sha256'), 'hex')
       )
       OR (
         delivery_address IS NULL
         AND quote_row.delivery_address_hash IS NOT NULL
       )
       OR (
         delivery_address IS NOT NULL
         AND quote_row.delivery_address_hash IS DISTINCT FROM
           encode(extensions.digest(convert_to(btrim(delivery_address), 'UTF8'), 'sha256'), 'hex')
       )
       OR (
         quote_row.expires_at <= now()
         AND quote_row.consumed_booking_id IS NULL
       ) THEN
      RAISE EXCEPTION 'Delivery fee quote is invalid or expired';
    END IF;

    IF quote_row.consumed_booking_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public."Booking"
      WHERE "BookingID" = quote_row.consumed_booking_id
        AND "KhachHangID" = customer_id
        AND "IdempotencyKey" = p_idempotency_key
    ) THEN
      RAISE EXCEPTION 'Delivery fee quote has already been used';
    END IF;

    pickup_distance := CASE WHEN pickup_address IS NOT NULL
      THEN quote_row.pickup_distance_meters ELSE 0 END;
    delivery_distance := CASE WHEN delivery_address IS NOT NULL
      THEN quote_row.delivery_distance_meters ELSE 0 END;

    -- First 3,000 meters are free on each leg. Each additional meter costs
    -- 5 VND; round the fee up to the next 1,000 VND.
    pickup_fee := ceil(greatest(pickup_distance - 3000, 0)::numeric * 5 / 1000) * 1000;
    delivery_fee := ceil(greatest(delivery_distance - 3000, 0)::numeric * 5 / 1000) * 1000;
  ELSIF p_delivery_fee_quote_id IS NOT NULL THEN
    RAISE EXCEPTION 'A delivery fee quote was supplied without a home delivery leg';
  END IF;

  -- Defer point redemption until the verified fee has been stored.
  booking_result := public.submit_laundry_booking_request(
    p_items => p_items,
    p_hinhthucnhando => p_hinhthucnhando,
    p_diachinhan => p_diachinhan,
    p_ngayhen => p_ngayhen,
    p_giohen => p_giohen,
    p_ghichu => p_ghichu,
    p_idempotency_key => p_idempotency_key,
    p_use_points => false,
    p_phuongthucthanhtoan => p_phuongthucthanhtoan,
    p_makhuyenmai => p_makhuyenmai
  );

  booking_id := (booking_result->>'bookingid')::bigint;
  IF p_delivery_fee_quote_id IS NOT NULL
     AND quote_row.consumed_booking_id IS NOT NULL
     AND quote_row.consumed_booking_id <> booking_id THEN
    RAISE EXCEPTION 'Delivery fee quote has already been used';
  END IF;
  total_delivery_fee := pickup_fee + delivery_fee;

  UPDATE public."Booking"
  SET "HinhThucGiaoDo" = p_hinhthucgiaodo,
      "DiaChiGiao" = delivery_address,
      "PickupDistanceMeters" = pickup_distance,
      "PickupDeliveryFee" = pickup_fee,
      "DeliveryDistanceMeters" = delivery_distance,
      "DeliveryFee" = delivery_fee
  WHERE "BookingID" = booking_id
    AND "KhachHangID" = customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found for current customer';
  END IF;

  IF p_delivery_fee_quote_id IS NOT NULL THEN
    UPDATE public.delivery_fee_quotes
    SET consumed_booking_id = booking_id
    WHERE id = p_delivery_fee_quote_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'Booking'
      AND column_name = 'HinhThucTraDo'
  ) THEN
    EXECUTE 'UPDATE public."Booking" SET "HinhThucTraDo" = $1 WHERE "BookingID" = $2'
      USING p_hinhthucgiaodo, booking_id;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'Booking'
      AND column_name = 'DiaChiTra'
  ) THEN
    EXECUTE 'UPDATE public."Booking" SET "DiaChiTra" = $1 WHERE "BookingID" = $2'
      USING delivery_address, booking_id;
  END IF;

  IF p_items IS NOT NULL AND coalesce(p_use_points, false) THEN
    booking_result := public.submit_laundry_order_cart_with_points(
      p_items,
      p_hinhthucnhando,
      p_diachinhan,
      p_ngayhen,
      p_giohen,
      p_ghichu,
      p_idempotency_key,
      true
    );
  END IF;

  RETURN booking_result || jsonb_build_object(
    'pickupdistancemeters', pickup_distance,
    'pickupdeliveryfee', pickup_fee,
    'deliverydistancemeters', delivery_distance,
    'deliveryfee', delivery_fee,
    'totaldeliveryfee', total_delivery_fee
  );
END;
$$;

ALTER FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text, uuid
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text, uuid
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.apply_booking_promotion_to_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_row public."Booking"%ROWTYPE;
  promotion public."KhuyenMai"%ROWTYPE;
  discount_amount numeric(18,2);
BEGIN
  IF NEW."BookingID" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO booking_row
  FROM public."Booking"
  WHERE "BookingID" = NEW."BookingID";

  IF NOT FOUND OR booking_row."KhuyenMaiID" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO promotion
  FROM public."KhuyenMai"
  WHERE "KhuyenMaiID" = booking_row."KhuyenMaiID";

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF promotion."GiaTriDonToiThieu" IS NOT NULL
     AND NEW."TongTien" < promotion."GiaTriDonToiThieu" THEN
    IF booking_row."KhuyenMaiDaTru" THEN
      UPDATE public."KhuyenMai"
      SET "SoLuongSuDung" = "SoLuongSuDung" + 1
      WHERE "KhuyenMaiID" = booking_row."KhuyenMaiID"
        AND "SoLuongSuDung" IS NOT NULL;
    END IF;

    UPDATE public."Booking"
    SET "KhuyenMaiID" = NULL,
        "KhuyenMaiDaTru" = false
    WHERE "BookingID" = NEW."BookingID";
    NEW."KhuyenMaiID" := NULL;
    NEW."TienGiamKhuyenMai" := 0;
    NEW."ThanhTien" := greatest(
      NEW."TongTien" + NEW."PhiGiaoHang"
        - greatest(NEW."TienGiamDoDiem", 0),
      0
    );
    RETURN NEW;
  END IF;

  discount_amount := CASE
    WHEN promotion."LoaiKhuyenMai" = 'Phần trăm'
      THEN NEW."TongTien" * promotion."GiaTriGiam" / 100
    ELSE promotion."GiaTriGiam"
  END;

  IF promotion."MucGiamToiDa" IS NOT NULL THEN
    discount_amount := least(discount_amount, promotion."MucGiamToiDa");
  END IF;

  NEW."KhuyenMaiID" := booking_row."KhuyenMaiID";
  NEW."TienGiamKhuyenMai" := greatest(
    least(discount_amount, NEW."TongTien"),
    0
  );
  NEW."ThanhTien" := greatest(
    NEW."TongTien" + NEW."PhiGiaoHang"
      - NEW."TienGiamKhuyenMai"
      - greatest(NEW."TienGiamDoDiem", 0),
    0
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.apply_booking_points_to_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_points integer;
  booking_discount numeric(18,2);
BEGIN
  IF NEW."BookingID" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT "DiemSuDung", "TienGiamDoDiem"
  INTO booking_points, booking_discount
  FROM public."Booking"
  WHERE "BookingID" = NEW."BookingID";

  IF FOUND THEN
    NEW."DiemSuDung" := booking_points;
    NEW."TienGiamDoDiem" := booking_discount;
    NEW."ThanhTien" := greatest(
      NEW."TongTien" + NEW."PhiGiaoHang"
        - greatest(NEW."TienGiamKhuyenMai", 0)
        - greatest(NEW."TienGiamDoDiem", 0),
      0
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.copy_booking_delivery_fee_to_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  pickup_fee numeric(12, 2);
  delivery_fee numeric(12, 2);
BEGIN
  IF NEW."BookingID" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT "PickupDeliveryFee", "DeliveryFee"
  INTO pickup_fee, delivery_fee
  FROM public."Booking"
  WHERE "BookingID" = NEW."BookingID";

  IF FOUND THEN
    NEW."PhiGiaoHang" := coalesce(pickup_fee, 0) + coalesce(delivery_fee, 0);
    NEW."ThanhTien" := greatest(
      NEW."TongTien" + NEW."PhiGiaoHang"
        - least(
          NEW."TongTien",
          greatest(NEW."TienGiamKhuyenMai", 0)
        )
        - greatest(NEW."TienGiamDoDiem", 0),
      0
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.sync_booking_delivery_fee_to_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  total_delivery_fee numeric(12, 2);
BEGIN
  total_delivery_fee := coalesce(NEW."PickupDeliveryFee", 0)
    + coalesce(NEW."DeliveryFee", 0);

  UPDATE public."DonHang"
  SET "PhiGiaoHang" = total_delivery_fee,
      "ThanhTien" = greatest(
        "TongTien" + total_delivery_fee
          - least(
            "TongTien",
            greatest("TienGiamKhuyenMai", 0)
          )
          - greatest("TienGiamDoDiem", 0),
        0
      )
  WHERE "BookingID" = NEW."BookingID";

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.sync_booking_delivery_fee_to_order()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS sync_booking_delivery_fee_to_order
  ON public."Booking";
CREATE TRIGGER sync_booking_delivery_fee_to_order
  AFTER UPDATE OF "PickupDeliveryFee", "DeliveryFee"
  ON public."Booking"
  FOR EACH ROW
  WHEN (
    OLD."PickupDeliveryFee" IS DISTINCT FROM NEW."PickupDeliveryFee"
    OR OLD."DeliveryFee" IS DISTINCT FROM NEW."DeliveryFee"
  )
  EXECUTE FUNCTION private.sync_booking_delivery_fee_to_order();

-- Correct orders that already exist for bookings whose delivery fee was
-- assigned after their order row was created.
UPDATE public."DonHang" AS order_row
SET "PhiGiaoHang" = coalesce(booking."PickupDeliveryFee", 0)
      + coalesce(booking."DeliveryFee", 0),
    "ThanhTien" = greatest(
      order_row."TongTien"
        + coalesce(booking."PickupDeliveryFee", 0)
        + coalesce(booking."DeliveryFee", 0)
        - least(
          order_row."TongTien",
          greatest(order_row."TienGiamKhuyenMai", 0)
        )
        - greatest(order_row."TienGiamDoDiem", 0),
      0
    )
FROM public."Booking" AS booking
WHERE booking."BookingID" = order_row."BookingID"
  AND (
    order_row."PhiGiaoHang" IS DISTINCT FROM
      coalesce(booking."PickupDeliveryFee", 0)
        + coalesce(booking."DeliveryFee", 0)
    OR order_row."ThanhTien" IS DISTINCT FROM greatest(
      order_row."TongTien"
        + coalesce(booking."PickupDeliveryFee", 0)
        + coalesce(booking."DeliveryFee", 0)
        - least(
          order_row."TongTien",
          greatest(order_row."TienGiamKhuyenMai", 0)
        )
        - greatest(order_row."TienGiamDoDiem", 0),
      0
    )
  );

NOTIFY pgrst, 'reload schema';
COMMIT;
