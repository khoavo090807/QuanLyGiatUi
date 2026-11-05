BEGIN;

CREATE OR REPLACE FUNCTION public.submit_laundry_order_cart(
  p_items jsonb,
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
AS $$
DECLARE
  customer_id bigint := private.current_customer_id();
  booking_row public."Booking"%ROWTYPE;
  booking_id bigint;
  detail_count integer := 0;
  total_amount numeric := 0;
  item jsonb;
  price_row record;
  measurement numeric;
  quantity numeric;
  weight_kg numeric;
  line_total numeric;
BEGIN
  IF auth.uid() IS NULL OR customer_id IS NULL THEN
    RAISE EXCEPTION 'An active customer account is required';
  END IF;
  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'An idempotency key is required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );

  SELECT * INTO booking_row
  FROM public."Booking"
  WHERE "IdempotencyKey" = p_idempotency_key;

  IF FOUND THEN
    IF booking_row."KhachHangID" <> customer_id THEN
      RAISE EXCEPTION 'Idempotency key is already in use';
    END IF;

    SELECT count(*), coalesce(sum("ThanhTien"), 0)
    INTO detail_count, total_amount
    FROM public."ChiTietBooking"
    WHERE "BookingID" = booking_row."BookingID";

    RETURN jsonb_build_object(
      'bookingid', booking_row."BookingID",
      'mabooking', booking_row."MaBooking",
      'trangthai', booking_row."TrangThai",
      'thanhtien', total_amount,
      'itemcount', detail_count
    );
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Cart must contain at least one item';
  END IF;
  IF p_hinhthucnhando IS NULL
     OR p_hinhthucnhando NOT IN ('Tại cửa hàng', 'Tại nhà') THEN
    RAISE EXCEPTION 'Unsupported pickup method';
  END IF;
  IF p_hinhthucnhando = 'Tại nhà'
     AND nullif(btrim(p_diachinhan), '') IS NULL THEN
    RAISE EXCEPTION 'A pickup address is required';
  END IF;
  IF p_ngayhen IS NULL OR p_ngayhen < current_date OR p_giohen IS NULL THEN
    RAISE EXCEPTION 'A current pickup appointment is required';
  END IF;

  INSERT INTO public."Booking" (
    "MaBooking", "KhachHangID", "HinhThucNhanDo", "DiaChiNhan",
    "HinhThucTraDo", "NgayHen", "GioHen", "GhiChu", "TrangThai",
    "IdempotencyKey"
  ) VALUES (
    'BK-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 24),
    customer_id,
    p_hinhthucnhando,
    CASE WHEN p_hinhthucnhando = 'Tại nhà' THEN nullif(btrim(p_diachinhan), '') END,
    'Tại cửa hàng',
    p_ngayhen,
    p_giohen,
    nullif(btrim(p_ghichu), ''),
    'ChoTiepNhan',
    p_idempotency_key
  )
  RETURNING "BookingID" INTO booking_id;

  UPDATE public."Booking"
  SET "MaBooking" = 'BK' || lpad(
    booking_id::text,
    greatest(4, length(booking_id::text)),
    '0'
  )
  WHERE "BookingID" = booking_id;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    SELECT bg.*,
      lower(btrim(coalesce(u."KyHieu", u."TenDonViTinh"))) AS unit_symbol
    INTO price_row
    FROM public."BangGia" chosen
    JOIN public."BangGia" bg
      ON bg."DichVuID" = chosen."DichVuID"
      AND bg."LoaiDoGiatID" = chosen."LoaiDoGiatID"
      AND bg."DonViTinhID" = chosen."DonViTinhID"
    JOIN public."DonViTinh" u ON u."DonViTinhID" = bg."DonViTinhID"
    WHERE chosen."BangGiaID" = (item->>'banggiaid')::bigint
      AND bg."TrangThai" = 'Hoạt động'
      AND (bg."NgayApDung" IS NULL OR bg."NgayApDung" <= current_date)
      AND (bg."NgayKetThuc" IS NULL OR bg."NgayKetThuc" >= current_date)
    ORDER BY bg."NgayApDung" DESC NULLS LAST, bg."BangGiaID" DESC
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No effective price is available for the selected tuple';
    END IF;

    measurement := (item->>'measurement')::numeric;
    IF measurement IS NULL OR measurement <= 0 OR measurement > 99999999.99 THEN
      RAISE EXCEPTION 'Invalid measurement';
    END IF;

    IF price_row.unit_symbol IN ('kg', 'kgs', 'kilogram') THEN
      measurement := round(measurement, 2);
      IF measurement <= 0 THEN
        RAISE EXCEPTION 'Invalid measurement';
      END IF;
      weight_kg := measurement;
      quantity := NULL;
      line_total := round(price_row."DonGia" * measurement, 0);
    ELSE
      IF measurement <> trunc(measurement) THEN
        RAISE EXCEPTION 'Piece quantity must be an integer';
      END IF;
      quantity := measurement;
      weight_kg := NULL;
      line_total := round(price_row."DonGia" * measurement, 0);
    END IF;

    INSERT INTO public."ChiTietBooking" (
      "BookingID", "DichVuID", "LoaiDoGiatID", "DonViTinhID",
      "SoLuong", "KhoiLuong", "DonGia", "ThanhTien", "GhiChu"
    ) VALUES (
      booking_id, price_row."DichVuID", price_row."LoaiDoGiatID",
      price_row."DonViTinhID", quantity, weight_kg, price_row."DonGia",
      line_total, nullif(btrim(p_ghichu), '')
    );

    detail_count := detail_count + 1;
    total_amount := total_amount + line_total;
  END LOOP;

  SELECT * INTO booking_row
  FROM public."Booking"
  WHERE "BookingID" = booking_id;

  RETURN jsonb_build_object(
    'bookingid', booking_id,
    'mabooking', booking_row."MaBooking",
    'trangthai', 'ChoTiepNhan',
    'thanhtien', total_amount,
    'itemcount', detail_count
  );
END;
$$;

COMMIT;
