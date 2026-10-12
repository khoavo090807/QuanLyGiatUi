BEGIN;

CREATE OR REPLACE FUNCTION private.notify_customers_new_promotion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  promotion_is_available boolean;
  promotion_was_available boolean := false;
  discount_label text;
  notification_title text;
  notification_message text;
BEGIN
  promotion_is_available := NEW."TrangThai" = 'Hoạt động'
    AND NEW."NgayBatDau" <= current_date
    AND NEW."NgayKetThuc" >= current_date
    AND (NEW."SoLuongSuDung" IS NULL OR NEW."SoLuongSuDung" > 0);

  IF TG_OP = 'UPDATE' THEN
    promotion_was_available := OLD."TrangThai" = 'Hoạt động'
      AND OLD."NgayBatDau" <= current_date
      AND OLD."NgayKetThuc" >= current_date
      AND (OLD."SoLuongSuDung" IS NULL OR OLD."SoLuongSuDung" > 0);
  END IF;

  IF NOT promotion_is_available OR promotion_was_available THEN
    RETURN NEW;
  END IF;

  discount_label := CASE
    WHEN NEW."LoaiKhuyenMai" = 'Phần trăm'
      THEN trim(to_char(NEW."GiaTriGiam", 'FM999999990.##')) || '%'
    ELSE trim(to_char(NEW."GiaTriGiam", 'FM999999990.##')) || 'đ'
  END;

  notification_title := left('Ưu đãi mới: ' || NEW."TenKhuyenMai", 200);
  notification_message := left(
    'Mã ' || NEW."MaKhuyenMai" || ' giảm ' || discount_label || '.' ||
      CASE
        WHEN NEW."GiaTriDonToiThieu" IS NOT NULL
          THEN ' Đơn tối thiểu ' ||
            trim(to_char(NEW."GiaTriDonToiThieu", 'FM999999999999990.##')) || 'đ.'
        ELSE ''
      END ||
      CASE
        WHEN nullif(btrim(NEW."DieuKienApDung"), '') IS NOT NULL
          THEN ' ' || btrim(NEW."DieuKienApDung") || '.'
        ELSE ''
      END ||
      ' Có hiệu lực đến ' || to_char(NEW."NgayKetThuc", 'DD/MM/YYYY') || '.',
    1000
  );

  INSERT INTO public."ThongBao" (
    "TaiKhoanID", "TieuDe", "NoiDung", "LoaiThongBao"
  )
  SELECT account."TaiKhoanID", notification_title, notification_message,
         'new_promotion'
  FROM public."TaiKhoan" AS account
  WHERE account."TrangThai" = 'Hoạt động'
    AND account."KhachHangID" IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public."TaiKhoan_VaiTro" AS account_role
      JOIN public."VaiTro" AS role
        ON role."VaiTroID" = account_role."VaiTroID"
      WHERE account_role."TaiKhoanID" = account."TaiKhoanID"
        AND role."TenVaiTro" = 'Khách hàng'
        AND role."TrangThai" = 'Hoạt động'
    );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_customers_new_promotion()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS notify_customers_new_promotion
  ON public."KhuyenMai";

CREATE TRIGGER notify_customers_new_promotion
AFTER INSERT OR UPDATE OF "TrangThai", "NgayBatDau", "NgayKetThuc", "SoLuongSuDung"
ON public."KhuyenMai"
FOR EACH ROW
EXECUTE FUNCTION private.notify_customers_new_promotion();

COMMIT;
