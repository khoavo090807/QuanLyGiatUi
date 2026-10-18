BEGIN;

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
  IF p_ngayhen IS NULL
     OR p_giohen IS NULL
      OR p_ngayhen + p_giohen < timezone('Asia/Ho_Chi_Minh', now()) THEN
    RAISE EXCEPTION 'Pickup appointment must be in the future';
  END IF;

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
    booking_result := public.submit_laundry_order_cart(
      p_items,
      p_hinhthucnhando,
      p_diachinhan,
      p_ngayhen,
      p_giohen,
      p_idempotency_key
    );
  END IF;

  booking_id := (booking_result->>'bookingid')::bigint;

  IF nullif(btrim(p_makhuyenmai), '') IS NOT NULL THEN
    PERFORM public.set_booking_promotion(booking_id, p_makhuyenmai);
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

  RETURN booking_result;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_laundry_booking_request(
  jsonb, text, text, date, time without time zone, text, uuid, boolean, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_laundry_booking_request(
  jsonb, text, text, date, time without time zone, text, uuid, boolean, text
) TO authenticated;

COMMIT;