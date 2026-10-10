-- Order chats can have multiple active accounts linked to the same customer.
-- Keep the order as the conversation boundary while RLS enforces ownership.
DROP POLICY IF EXISTS laundry_customer_order_message_read ON public."TinNhan";
CREATE POLICY laundry_customer_order_message_read
  ON public."TinNhan"
  FOR SELECT
  TO authenticated
  USING (
    "DonHangID" IS NOT NULL
    AND NOT private.is_messaging_staff()
    AND (SELECT private.can_access_order("DonHangID"::bigint))
  );

CREATE OR REPLACE FUNCTION public.mark_chat_thread_read(
  p_peer_account_id integer,
  p_order_id integer DEFAULT NULL
)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  WITH updated AS (
    UPDATE public."TinNhan" AS m SET "TrangThai" = 'Đã đọc'
    WHERE m."DonHangID" IS NOT DISTINCT FROM p_order_id
      AND m."TrangThai" IN ('Đã gửi', 'Đã nhận')
      AND (
        (NOT private.is_messaging_staff()
          AND (
            m."NguoiNhanID" = private.current_account_id()
            OR (
              p_order_id IS NOT NULL
              AND (SELECT private.can_access_order(p_order_id::bigint))
            )
          )
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
          ))
        OR (private.is_messaging_staff()
          AND m."NguoiGuiID" = p_peer_account_id
          AND m."NguoiNhanID" IN (
            SELECT a."TaiKhoanID" FROM public."TaiKhoan" AS a
            WHERE a."NhanVienID" IS NOT NULL AND EXISTS (
              SELECT 1 FROM public."TaiKhoan_VaiTro" AS av
              JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
              WHERE av."TaiKhoanID" = a."TaiKhoanID"
                AND r."TrangThai" = 'Hoạt động'
                AND (r."TenVaiTro" IN ('Nhân viên','Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
            )
          )
          AND EXISTS (
            SELECT 1 FROM public."TaiKhoan" AS customer
            WHERE customer."TaiKhoanID" = p_peer_account_id
              AND customer."KhachHangID" IS NOT NULL
          ))
      )
    RETURNING 1
  )
  SELECT count(*)::integer FROM updated;
$function$;

REVOKE ALL ON FUNCTION public.mark_chat_thread_read(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_chat_thread_read(integer, integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
