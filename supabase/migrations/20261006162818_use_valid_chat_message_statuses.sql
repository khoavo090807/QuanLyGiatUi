CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_recipient_account_id integer,
  p_content text,
  p_order_id integer DEFAULT NULL
)
RETURNS SETOF public."TinNhan"
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  INSERT INTO public."TinNhan"
    ("NguoiGuiID", "NguoiNhanID", "DonHangID", "NoiDung", "ThoiGianGui", "TrangThai")
  SELECT sender."TaiKhoanID", recipient."TaiKhoanID", p_order_id, btrim(p_content),
    timezone('utc', now())::timestamp, 'Đã gửi'
  FROM public."TaiKhoan" AS sender
  JOIN public."TaiKhoan" AS recipient ON recipient."TaiKhoanID" = p_recipient_account_id
  WHERE auth.uid() IS NOT NULL
    AND sender."TaiKhoanID" = private.current_account_id()
    AND sender."TrangThai" = 'Hoạt động'
    AND recipient."TrangThai" = 'Hoạt động'
    AND nullif(btrim(p_content), '') IS NOT NULL
    AND char_length(btrim(p_content)) <= 2000
    AND (
      (NOT private.is_messaging_staff() AND sender."KhachHangID" IS NOT NULL
        AND recipient."TaiKhoanID" = private.default_support_account_id()
        AND (p_order_id IS NULL OR (
          (SELECT private.can_access_order(p_order_id::bigint))
          AND EXISTS (SELECT 1 FROM public."DonHang" d
            WHERE d."DonHangID" = p_order_id AND d."KhachHangID" = sender."KhachHangID")
        )))
      OR (private.is_messaging_staff() AND recipient."KhachHangID" IS NOT NULL
        AND (p_order_id IS NULL OR EXISTS (SELECT 1 FROM public."DonHang" d
          WHERE d."DonHangID" = p_order_id AND d."KhachHangID" = recipient."KhachHangID")))
    )
  RETURNING *;
$function$;

CREATE OR REPLACE FUNCTION public.get_staff_chat_inbox()
RETURNS TABLE (
  customer_account_id integer,
  customer_name text,
  customer_avatar_url text,
  order_id integer,
  order_number text,
  last_message text,
  last_message_at timestamp without time zone,
  last_sender_account_id integer,
  unread_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  WITH conversations AS (
    SELECT DISTINCT ON (
      CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END,
      m."DonHangID"
    )
      CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END AS customer_account_id,
      m."DonHangID" AS order_id, m."NoiDung" AS last_message,
      m."ThoiGianGui" AS last_message_at, m."NguoiGuiID" AS last_sender_account_id
    FROM public."TinNhan" AS m
    JOIN public."TaiKhoan" AS sender ON sender."TaiKhoanID" = m."NguoiGuiID"
    JOIN public."TaiKhoan" AS recipient ON recipient."TaiKhoanID" = m."NguoiNhanID"
    WHERE sender."KhachHangID" IS NOT NULL OR recipient."KhachHangID" IS NOT NULL
    ORDER BY
      CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END,
      m."DonHangID", m."ThoiGianGui" DESC, m."TinNhanID" DESC
  )
  SELECT c.customer_account_id,
    coalesce(k."HoTen", a."TenDangNhap", 'Khách hàng')::text,
    coalesce(k."AvatarUrl", a."AvatarURL")::text,
    c.order_id, d."MaDonHang"::text, c.last_message, c.last_message_at,
    c.last_sender_account_id,
    (SELECT count(*) FROM public."TinNhan" AS m
      JOIN public."TaiKhoan" AS sender ON sender."TaiKhoanID" = m."NguoiGuiID"
      WHERE sender."KhachHangID" IS NOT NULL
        AND m."NguoiGuiID" = c.customer_account_id
        AND m."DonHangID" IS NOT DISTINCT FROM c.order_id
        AND m."TrangThai" IN ('Đã gửi', 'Đã nhận'))
  FROM conversations AS c
  JOIN public."TaiKhoan" AS a ON a."TaiKhoanID" = c.customer_account_id
  LEFT JOIN public."KhachHang" AS k ON k."KhachHangID" = a."KhachHangID"
  LEFT JOIN public."DonHang" AS d ON d."DonHangID" = c.order_id
  WHERE auth.uid() IS NOT NULL AND private.is_messaging_staff()
  ORDER BY c.last_message_at DESC;
$function$;

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
          AND m."NguoiNhanID" = private.current_account_id()
          AND EXISTS (
            SELECT 1 FROM public."TaiKhoan" AS sender
            WHERE sender."TaiKhoanID" = m."NguoiGuiID" AND sender."NhanVienID" IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM public."TaiKhoan_VaiTro" AS av
                JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
                WHERE av."TaiKhoanID" = sender."TaiKhoanID" AND r."TrangThai" = 'Hoạt động'
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
              WHERE av."TaiKhoanID" = a."TaiKhoanID" AND r."TrangThai" = 'Hoạt động'
                AND (r."TenVaiTro" IN ('Nhân viên','Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
            )
          )
          AND EXISTS (SELECT 1 FROM public."TaiKhoan" AS customer
            WHERE customer."TaiKhoanID" = p_peer_account_id AND customer."KhachHangID" IS NOT NULL))
      )
    RETURNING 1
  )
  SELECT count(*)::integer FROM updated;
$function$;

REVOKE ALL ON FUNCTION public.send_chat_message(integer, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_staff_chat_inbox() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_chat_thread_read(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_chat_message(integer, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_staff_chat_inbox() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_chat_thread_read(integer, integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
