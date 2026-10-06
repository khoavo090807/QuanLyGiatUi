BEGIN;

ALTER TABLE public."Booking"
  ADD COLUMN IF NOT EXISTS "PickupDistanceMeters" integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "PickupDeliveryFee" numeric(12, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "DeliveryDistanceMeters" integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "DeliveryFee" numeric(12, 2) NOT NULL DEFAULT 0;

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
        - NEW."TienGiamDoDiem" - NEW."TienGiamKhuyenMai",
      0
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.copy_booking_delivery_fee_to_order()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS set_booking_delivery_fee_on_order ON public."DonHang";
CREATE TRIGGER set_booking_delivery_fee_on_order
  BEFORE INSERT ON public."DonHang"
  FOR EACH ROW EXECUTE FUNCTION private.copy_booking_delivery_fee_to_order();

DO $$
BEGIN
  ALTER TABLE public."Booking"
    ADD CONSTRAINT "Booking_delivery_distance_nonnegative"
    CHECK ("PickupDistanceMeters" >= 0 AND "DeliveryDistanceMeters" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public."Booking"
    ADD CONSTRAINT "Booking_delivery_fee_nonnegative"
    CHECK ("PickupDeliveryFee" >= 0 AND "DeliveryFee" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.delivery_fee_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL,
  pickup_address_hash text,
  delivery_address_hash text,
  pickup_distance_meters integer NOT NULL DEFAULT 0,
  delivery_distance_meters integer NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  consumed_booking_id integer REFERENCES public."Booking" ("BookingID") ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT delivery_fee_quotes_nonnegative_distances CHECK (
    pickup_distance_meters >= 0 AND delivery_distance_meters >= 0
  )
);

CREATE TABLE IF NOT EXISTS public.delivery_fee_quote_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.delivery_fee_quotes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.delivery_fee_quotes FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.delivery_fee_quotes TO service_role;
ALTER TABLE public.delivery_fee_quote_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.delivery_fee_quote_attempts FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.delivery_fee_quote_attempts TO service_role;
CREATE INDEX IF NOT EXISTS delivery_fee_quotes_expires_at_idx
  ON public.delivery_fee_quotes (expires_at);
CREATE INDEX IF NOT EXISTS delivery_fee_quote_attempts_user_created_idx
  ON public.delivery_fee_quote_attempts (auth_user_id, created_at DESC);

DROP FUNCTION IF EXISTS public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text
);

CREATE FUNCTION public.submit_laundry_booking_with_delivery(
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

  booking_result := public.submit_laundry_booking_request(
    p_items => p_items,
    p_hinhthucnhando => p_hinhthucnhando,
    p_diachinhan => p_diachinhan,
    p_ngayhen => p_ngayhen,
    p_giohen => p_giohen,
    p_ghichu => p_ghichu,
    p_idempotency_key => p_idempotency_key,
    p_use_points => p_use_points,
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

COMMENT ON TABLE public.delivery_fee_quotes IS
  'Short-lived, service-role-only route quotes. Stores address hashes rather than raw address text and is consumed atomically by booking submission.';

NOTIFY pgrst, 'reload schema';
COMMIT;
