CREATE OR REPLACE FUNCTION public.get_customer_loyalty()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_id bigint := (SELECT private.current_customer_id());
  current_points integer;
  active_vouchers jsonb;
BEGIN
  IF customer_id IS NULL THEN
    RAISE EXCEPTION 'An active customer account is required';
  END IF;

  SELECT coalesce(points."DiemHienTai", 0)
  INTO current_points
  FROM public."DiemTichLuy" AS points
  WHERE points."KhachHangID" = customer_id;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'khuyenmaiid', promotion."KhuyenMaiID",
        'makhuyenmai', promotion."MaKhuyenMai",
        'tenkhuyenmai', promotion."TenKhuyenMai",
        'loaikhuyenmai', promotion."LoaiKhuyenMai",
        'giatrigiam', promotion."GiaTriGiam",
        'ngayketthuc', promotion."NgayKetThuc",
        'giatridontoithieu', promotion."GiaTriDonToiThieu",
        'mucgiamtoida', promotion."MucGiamToiDa",
        'dieukienapdung', promotion."DieuKienApDung"
      )
      ORDER BY promotion."NgayKetThuc"
    ),
    '[]'::jsonb
  )
  INTO active_vouchers
  FROM public."KhuyenMai" AS promotion
  WHERE promotion."TrangThai" = 'Hoạt động'
    AND promotion."NgayBatDau" <= current_date
    AND promotion."NgayKetThuc" >= current_date
    AND (
      promotion."SoLuongSuDung" IS NULL
      OR promotion."SoLuongSuDung" > 0
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public."Booking" AS booking
      WHERE booking."KhachHangID" = customer_id
        AND booking."KhuyenMaiID" = promotion."KhuyenMaiID"
        AND booking."TrangThai" <> 'DaHuy'
    );

  RETURN jsonb_build_object(
    'points', coalesce(current_points, 0),
    'vouchers', active_vouchers
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_customer_loyalty() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_loyalty() TO authenticated;