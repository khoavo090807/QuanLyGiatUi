CREATE OR REPLACE FUNCTION public.mark_chat_thread_read(
  p_peer_account_id integer,
  p_order_id integer DEFAULT NULL
)
RETURNS integer
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH updated AS (
    UPDATE public."TinNhan" AS m
    SET "TrangThai" = 'Đã đọc'
    WHERE m."DonHangID" IS NOT DISTINCT FROM p_order_id
      AND m."TrangThai" = 'Chưa đọc'
      AND (
        (
          NOT private.is_messaging_staff()
          AND m."NguoiNhanID" = private.current_account_id()
          AND EXISTS (
            SELECT 1 FROM public."TaiKhoan" AS sender
            WHERE sender."TaiKhoanID" = m."NguoiGuiID"
              AND sender."NhanVienID" IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM public."TaiKhoan_VaiTro" AS av
                JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
                WHERE av."TaiKhoanID" = sender."TaiKhoanID"
                  AND r."TrangThai" = 'Hoạt động'
                  AND (r."TenVaiTro" IN ('Nhân viên','Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
              )
          )
        )
        OR (
          private.is_messaging_staff()
          AND m."NguoiGuiID" = p_peer_account_id
          AND m."NguoiNhanID" IN (
            SELECT a."TaiKhoanID" FROM public."TaiKhoan" a
            WHERE a."NhanVienID" IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM public."TaiKhoan_VaiTro" av
                JOIN public."VaiTro" r ON r."VaiTroID" = av."VaiTroID"
                WHERE av."TaiKhoanID" = a."TaiKhoanID"
                  AND r."TrangThai" = 'Hoạt động'
                  AND (r."TenVaiTro" IN ('Nhân viên','Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
              )
          )
          AND EXISTS (
            SELECT 1 FROM public."TaiKhoan" customer
            WHERE customer."TaiKhoanID" = p_peer_account_id
              AND customer."KhachHangID" IS NOT NULL
          )
        )
      )
    RETURNING 1
  )
  SELECT count(*)::integer FROM updated;
$function$;

REVOKE ALL ON FUNCTION public.mark_chat_thread_read(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_chat_thread_read(integer, integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
