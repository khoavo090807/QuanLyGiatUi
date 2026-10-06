BEGIN;

ALTER TABLE public."Booking"
  ADD COLUMN IF NOT EXISTS "HinhThucGiaoDo" character varying(30);

ALTER TABLE public."Booking"
  ADD COLUMN IF NOT EXISTS "DiaChiGiao" text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Booking'
      AND column_name = 'HinhThucTraDo'
  ) THEN
    UPDATE public."Booking"
    SET "HinhThucGiaoDo" = COALESCE(
      NULLIF(btrim("HinhThucGiaoDo"), ''),
      CASE
        WHEN "HinhThucTraDo" IN ('Tại cửa hàng', 'Tại nhà') THEN "HinhThucTraDo"
        ELSE NULL
      END,
      'Tại cửa hàng'
    )
    WHERE "HinhThucGiaoDo" IS NULL OR btrim("HinhThucGiaoDo") = '';
  ELSE
    UPDATE public."Booking"
    SET "HinhThucGiaoDo" = COALESCE(NULLIF(btrim("HinhThucGiaoDo"), ''), 'Tại cửa hàng')
    WHERE "HinhThucGiaoDo" IS NULL OR btrim("HinhThucGiaoDo") = '';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Booking'
      AND column_name = 'DiaChiTra'
  ) THEN
    UPDATE public."Booking"
    SET "DiaChiGiao" = COALESCE(NULLIF(btrim("DiaChiGiao"), ''), NULLIF(btrim("DiaChiTra"), ''))
    WHERE "DiaChiGiao" IS NULL OR btrim("DiaChiGiao") = '';
  END IF;
END $$;

ALTER TABLE public."Booking"
  ALTER COLUMN "HinhThucGiaoDo" SET DEFAULT 'Tại cửa hàng';

UPDATE public."Booking"
SET "HinhThucGiaoDo" = 'Tại cửa hàng'
WHERE "HinhThucGiaoDo" IS NULL;

ALTER TABLE public."Booking"
  ALTER COLUMN "HinhThucGiaoDo" SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE public."Booking"
    ADD CONSTRAINT "Booking_HinhThucGiaoDo_check"
    CHECK ("HinhThucGiaoDo" IN ('Tại cửa hàng', 'Tại nhà'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public."Booking"
  ALTER COLUMN "DiaChiNhan" TYPE text;

DROP FUNCTION IF EXISTS public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text
);

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
  p_diachigiao text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_result jsonb;
  customer_id bigint := (SELECT private.current_customer_id());
  booking_id bigint;
BEGIN
  IF p_hinhthucgiaodo IS NULL
     OR p_hinhthucgiaodo NOT IN ('Tại cửa hàng', 'Tại nhà') THEN
    RAISE EXCEPTION 'Unsupported delivery method';
  END IF;

  IF p_hinhthucgiaodo = 'Tại nhà'
     AND nullif(btrim(COALESCE(p_diachigiao, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Delivery address is required';
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

  UPDATE public."Booking"
  SET "HinhThucGiaoDo" = p_hinhthucgiaodo,
      "DiaChiGiao" = CASE
        WHEN p_hinhthucgiaodo = 'Tại nhà' THEN nullif(btrim(p_diachigiao), '')
        ELSE NULL
      END
  WHERE "BookingID" = booking_id
    AND "KhachHangID" = customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found for current customer';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Booking'
      AND column_name = 'HinhThucTraDo'
  ) THEN
    EXECUTE
      'UPDATE public."Booking" SET "HinhThucTraDo" = $1 WHERE "BookingID" = $2'
      USING p_hinhthucgiaodo, booking_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Booking'
      AND column_name = 'DiaChiTra'
  ) THEN
    EXECUTE
      'UPDATE public."Booking" SET "DiaChiTra" = $1 WHERE "BookingID" = $2'
      USING CASE
        WHEN p_hinhthucgiaodo = 'Tại nhà' THEN nullif(btrim(p_diachigiao), '')
        ELSE NULL
      END, booking_id;
  END IF;

  RETURN booking_result;
END;
$$;

ALTER FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text, text
) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
