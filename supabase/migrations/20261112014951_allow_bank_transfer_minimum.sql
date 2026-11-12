BEGIN;

CREATE OR REPLACE FUNCTION public.submit_laundry_booking_with_requested_services(
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
  p_delivery_fee_quote_id uuid DEFAULT NULL,
  p_requested_services jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_result jsonb;
  booking_id integer;
  customer_id integer := (SELECT private.current_customer_id());
  booking_subtotal numeric(18, 2) := 0;
  delivery_fee numeric(18, 2) := 0;
  points_discount numeric(18, 2) := 0;
  promotion_discount numeric(18, 2) := 0;
  final_amount numeric(18, 2) := 0;
  promotion_id integer;
  promotion public."KhuyenMai"%ROWTYPE;
BEGIN
  IF customer_id IS NULL OR (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'An active customer account is required';
  END IF;
  IF p_requested_services IS NOT NULL
     AND jsonb_typeof(p_requested_services) <> 'array' THEN
    RAISE EXCEPTION 'Requested services must be a JSON array';
  END IF;
  IF jsonb_array_length(coalesce(p_requested_services, '[]'::jsonb)) > 50 THEN
    RAISE EXCEPTION 'A booking can contain at most 50 requested services';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(p_requested_services, '[]'::jsonb)) AS request(item)
    WHERE jsonb_typeof(item) <> 'object'
       OR coalesce(item->>'service_id', '') !~ '^[1-9][0-9]*$'
       OR coalesce(item->>'garment_id', '') !~ '^[1-9][0-9]*$'
       OR coalesce(item->>'unit_id', '') !~ '^[1-9][0-9]*$'
  ) THEN
    RAISE EXCEPTION 'Each requested service needs valid service, garment, and unit IDs';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(coalesce(p_requested_services, '[]'::jsonb)) AS request(
      service_id integer,
      garment_id integer,
      unit_id integer
    )
    WHERE NOT EXISTS (
      SELECT 1
      FROM public."BangGia" AS price
      WHERE price."DichVuID" = request.service_id
        AND price."LoaiDoGiatID" = request.garment_id
        AND price."DonViTinhID" = request.unit_id
        AND price."TrangThai" = 'Hoạt động'
    )
  ) THEN
    RAISE EXCEPTION 'A requested service is no longer available';
  END IF;

  booking_result := public.submit_laundry_booking_with_delivery(
    p_items => p_items,
    p_hinhthucnhando => p_hinhthucnhando,
    p_hinhthucgiaodo => p_hinhthucgiaodo,
    p_diachinhan => p_diachinhan,
    p_ngayhen => p_ngayhen,
    p_giohen => p_giohen,
    p_ghichu => p_ghichu,
    p_idempotency_key => p_idempotency_key,
    p_use_points => p_use_points,
    p_phuongthucthanhtoan => p_phuongthucthanhtoan,
    p_makhuyenmai => p_makhuyenmai,
    p_diachigiao => p_diachigiao,
    p_delivery_fee_quote_id => p_delivery_fee_quote_id
  );
  booking_id := (booking_result->>'bookingid')::integer;

  IF p_phuongthucthanhtoan = 'Chuyển khoản' THEN
    SELECT
      coalesce((
        SELECT sum(detail."ThanhTien")
        FROM public."ChiTietBooking" AS detail
        WHERE detail."BookingID" = booking."BookingID"
      ), 0),
      coalesce(booking."PickupDeliveryFee", 0)
        + coalesce(booking."DeliveryFee", 0),
      coalesce(booking."TienGiamDoDiem", 0),
      booking."KhuyenMaiID"
    INTO booking_subtotal, delivery_fee, points_discount, promotion_id
    FROM public."Booking" AS booking
    WHERE booking."BookingID" = (booking_result->>'bookingid')::integer
      AND booking."KhachHangID" = customer_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Booking not found for current customer';
    END IF;

    IF promotion_id IS NOT NULL THEN
      SELECT * INTO promotion
      FROM public."KhuyenMai"
      WHERE "KhuyenMaiID" = promotion_id;

      IF FOUND
         AND promotion."TrangThai" = 'Hoạt động'
         AND promotion."NgayBatDau" <= current_date
         AND promotion."NgayKetThuc" >= current_date
         AND (promotion."GiaTriDonToiThieu" IS NULL
              OR booking_subtotal >= promotion."GiaTriDonToiThieu") THEN
        promotion_discount := CASE
          WHEN promotion."LoaiKhuyenMai" = 'Phần trăm'
            THEN booking_subtotal * promotion."GiaTriGiam" / 100
          ELSE promotion."GiaTriGiam"
        END;
        IF promotion."MucGiamToiDa" IS NOT NULL THEN
          promotion_discount := least(promotion_discount, promotion."MucGiamToiDa");
        END IF;
        promotion_discount := greatest(least(promotion_discount, booking_subtotal), 0);
      END IF;
    END IF;

    final_amount := greatest(
      booking_subtotal + delivery_fee - points_discount - promotion_discount,
      0
    );
    IF final_amount <= 10000 THEN
      RAISE EXCEPTION 'Bank transfer is only available when the total payment is greater than 10000 VND';
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public."Booking"
    WHERE "BookingID" = (booking_result->>'bookingid')::integer
      AND "KhachHangID" = customer_id
      AND "TrangThai" = 'ChoTiepNhan'
  ) THEN
    RETURN booking_result;
  END IF;

  DELETE FROM public."BookingYeuCauDichVu"
  WHERE "BookingID" = (booking_result->>'bookingid')::integer;

  INSERT INTO public."BookingYeuCauDichVu" (
    "BookingID", "DichVuID", "LoaiDoGiatID", "DonViTinhID"
  )
  SELECT (booking_result->>'bookingid')::integer, service_id, garment_id, unit_id
  FROM jsonb_to_recordset(coalesce(p_requested_services, '[]'::jsonb)) AS request(
    service_id integer,
    garment_id integer,
    unit_id integer
  );

  RETURN booking_result;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_laundry_booking_with_requested_services(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text, uuid, jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_with_requested_services(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text, uuid, jsonb
) TO authenticated;

COMMIT;
