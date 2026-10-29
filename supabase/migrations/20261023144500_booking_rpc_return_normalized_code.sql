-- Return the canonical code written by the Booking insert trigger.
CREATE OR REPLACE FUNCTION public.submit_laundry_booking_without_details(
  p_hinhthucnhando text,
  p_diachinhan text,
  p_ngayhen date,
  p_giohen time without time zone,
  p_ghichu text,
  p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  customer_id bigint := (SELECT private.current_customer_id());
  existing_booking record;
  booking_id bigint;
  booking_number text;
BEGIN
  IF customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  IF p_hinhthucnhando IS NULL OR p_hinhthucnhando NOT IN ('Tại cửa hàng','Tại nhà') THEN RAISE EXCEPTION 'Unsupported pickup method'; END IF;
  IF p_hinhthucnhando='Tại nhà' AND nullif(btrim(p_diachinhan),'') IS NULL THEN RAISE EXCEPTION 'A pickup address is required'; END IF;
  IF p_ngayhen IS NULL OR p_ngayhen<current_date OR p_giohen IS NULL THEN RAISE EXCEPTION 'A current pickup appointment is required'; END IF;
  SELECT * INTO existing_booking
  FROM public."Booking"
  WHERE "IdempotencyKey" = p_idempotency_key
    AND "KhachHangID" = customer_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'bookingid', existing_booking."BookingID",
      'mabooking', existing_booking."MaBooking",
      'trangthai', existing_booking."TrangThai",
      'thanhtien', 0,
      'itemcount', 0
    );
  END IF;
  IF EXISTS(SELECT 1 FROM public."Booking" WHERE "IdempotencyKey"=p_idempotency_key) THEN RAISE EXCEPTION 'Idempotency key is already in use'; END IF;
  booking_number := 'BK-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') ||
    '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  INSERT INTO public."Booking" (
    "MaBooking", "KhachHangID", "HinhThucNhanDo", "DiaChiNhan", "HinhThucTraDo",
    "NgayHen", "GioHen", "GhiChu", "TrangThai", "IdempotencyKey"
  ) VALUES (
    booking_number, customer_id, p_hinhthucnhando,
    nullif(btrim(p_diachinhan), ''), 'Tại cửa hàng', p_ngayhen, p_giohen,
    nullif(btrim(p_ghichu), ''), 'ChoTiepNhan', p_idempotency_key
  ) RETURNING "BookingID", "MaBooking" INTO booking_id, booking_number;
  RETURN jsonb_build_object(
    'bookingid', booking_id,
    'mabooking', booking_number,
    'trangthai', 'ChoTiepNhan',
    'thanhtien', 0,
    'itemcount', 0
  );
END;
$function$;
