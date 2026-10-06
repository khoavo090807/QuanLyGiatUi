BEGIN;

ALTER TABLE public."Booking"
  ADD COLUMN "HinhThucGiaoDo" character varying(30)
  NOT NULL DEFAULT 'Tại cửa hàng',
  ADD CONSTRAINT "Booking_HinhThucGiaoDo_check"
  CHECK ("HinhThucGiaoDo" IN ('Tại cửa hàng', 'Tại nhà'));

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
  p_makhuyenmai text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  booking_result jsonb;
  customer_id bigint := (SELECT private.current_customer_id());
BEGIN
  IF p_hinhthucgiaodo IS NULL
     OR p_hinhthucgiaodo NOT IN ('Tại cửa hàng', 'Tại nhà') THEN
    RAISE EXCEPTION 'Unsupported delivery method';
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

  UPDATE public."Booking"
  SET "HinhThucGiaoDo" = p_hinhthucgiaodo
  WHERE "BookingID" = (booking_result->>'bookingid')::bigint
    AND "KhachHangID" = customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found for current customer';
  END IF;

  RETURN booking_result;
END;
$$;

ALTER FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_with_delivery(
  jsonb, text, text, text, date, time without time zone, text, uuid,
  boolean, text, text
) TO authenticated, service_role;

COMMIT;