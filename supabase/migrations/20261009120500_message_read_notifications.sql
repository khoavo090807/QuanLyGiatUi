CREATE OR REPLACE FUNCTION public.notify_customer_of_store_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recipient_customer_id integer;
  sender_is_staff boolean;
  recipient_is_staff boolean;
BEGIN
  SELECT a."KhachHangID"
    INTO recipient_customer_id
  FROM public."TaiKhoan" AS a
  WHERE a."TaiKhoanID" = NEW."NguoiNhanID"
    AND a."TrangThai" = 'Hoạt động';

  SELECT EXISTS (
    SELECT 1
    FROM public."TaiKhoan" AS a
    JOIN public."TaiKhoan_VaiTro" AS av ON av."TaiKhoanID" = a."TaiKhoanID"
    JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
    WHERE a."TaiKhoanID" = NEW."NguoiGuiID"
      AND a."NhanVienID" IS NOT NULL
      AND a."TrangThai" = 'Hoạt động'
      AND r."TrangThai" = 'Hoạt động'
      AND (r."TenVaiTro" IN ('Nhân viên', 'Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
  ) INTO sender_is_staff;

  IF recipient_customer_id IS NOT NULL THEN
    INSERT INTO public."ThongBao" (
      "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao",
      "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
    )
    SELECT customer_account."TaiKhoanID", NEW."DonHangID", NEW."TinNhanID",
      'new_message',
      CASE WHEN sender_is_staff THEN 'Tin nhắn mới từ cửa hàng' ELSE 'Tin nhắn mới' END,
      left(CASE WHEN sender_is_staff THEN 'Cửa hàng: ' ELSE 'Tin nhắn: ' END || NEW."NoiDung", 1000),
      timezone('utc', now())::timestamp, false
    FROM public."TaiKhoan" AS customer_account
    WHERE customer_account."KhachHangID" = recipient_customer_id
      AND customer_account."TrangThai" = 'Hoạt động'
      AND customer_account."TaiKhoanID" <> NEW."NguoiGuiID"
      AND (
        NEW."DonHangID" IS NULL
        OR EXISTS (
          SELECT 1 FROM public."DonHang" AS d
          WHERE d."DonHangID" = NEW."DonHangID"
            AND d."KhachHangID" = recipient_customer_id
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public."ThongBao" AS existing
        WHERE existing."TaiKhoanID" = customer_account."TaiKhoanID"
          AND existing."TinNhanID" = NEW."TinNhanID"
          AND existing."LoaiThongBao" = 'new_message'
      );
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public."TaiKhoan" AS a
      JOIN public."TaiKhoan_VaiTro" AS av ON av."TaiKhoanID" = a."TaiKhoanID"
      JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
      WHERE a."TaiKhoanID" = NEW."NguoiNhanID"
        AND a."NhanVienID" IS NOT NULL
        AND a."TrangThai" = 'Hoạt động'
        AND r."TrangThai" = 'Hoạt động'
        AND (r."TenVaiTro" IN ('Nhân viên', 'Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
    ) INTO recipient_is_staff;

    IF recipient_is_staff THEN
      INSERT INTO public."ThongBao" (
        "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao",
        "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
      ) VALUES (
        NEW."NguoiNhanID", NEW."DonHangID", NEW."TinNhanID", 'new_message',
        'Tin nhắn mới từ khách hàng', left('Khách hàng: ' || NEW."NoiDung", 1000),
        timezone('utc', now())::timestamp, false
      );
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

-- Bring existing unread messages into the notification inbox for every active
-- account linked to the recipient customer. Read messages do not create a new
-- unread alert.
INSERT INTO public."ThongBao" (
  "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao",
  "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
)
SELECT target."TaiKhoanID", m."DonHangID", m."TinNhanID", 'new_message',
  'Tin nhắn mới', left('Tin nhắn: ' || m."NoiDung", 1000),
  timezone('utc', now())::timestamp, false
FROM public."TinNhan" AS m
JOIN public."TaiKhoan" AS recipient ON recipient."TaiKhoanID" = m."NguoiNhanID"
JOIN public."TaiKhoan" AS sender ON sender."TaiKhoanID" = m."NguoiGuiID"
JOIN public."TaiKhoan" AS target
  ON target."KhachHangID" = recipient."KhachHangID"
  AND target."TrangThai" = 'Hoạt động'
WHERE recipient."KhachHangID" IS NOT NULL
  AND sender."KhachHangID" IS DISTINCT FROM recipient."KhachHangID"
  AND m."TrangThai" IN ('Đã gửi', 'Đã nhận')
  AND (
    m."DonHangID" IS NULL
    OR EXISTS (
      SELECT 1 FROM public."DonHang" AS d
      WHERE d."DonHangID" = m."DonHangID"
        AND d."KhachHangID" = recipient."KhachHangID"
    )
  )
  AND NOT EXISTS (
    SELECT 1 FROM public."ThongBao" AS existing
    WHERE existing."TaiKhoanID" = target."TaiKhoanID"
      AND existing."TinNhanID" = m."TinNhanID"
      AND existing."LoaiThongBao" = 'new_message'
  );

CREATE OR REPLACE FUNCTION public.mark_chat_thread_read(
  p_peer_account_id integer,
  p_order_id integer DEFAULT NULL
)
RETURNS integer
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = ''
AS $function$
  WITH customer_accounts AS (
    SELECT a."TaiKhoanID"
    FROM public."TaiKhoan" AS a
    WHERE a."KhachHangID" = (SELECT private.current_customer_id())
  ),
  updated AS (
    UPDATE public."TinNhan" AS m SET "TrangThai" = 'Đã đọc'
    WHERE m."DonHangID" IS NOT DISTINCT FROM p_order_id
      AND m."TrangThai" IN ('Đã gửi', 'Đã nhận')
      AND (
        (NOT private.is_messaging_staff()
          AND m."NguoiNhanID" IN (SELECT "TaiKhoanID" FROM customer_accounts)
          AND (p_order_id IS NULL OR (SELECT private.can_access_order(p_order_id::bigint)))
        )
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
    RETURNING m."TinNhanID"
  ),
  synced_notifications AS (
    UPDATE public."ThongBao" AS n SET "DaDoc" = true
    WHERE NOT private.is_messaging_staff()
      AND n."LoaiThongBao" = 'new_message'
      AND n."TaiKhoanID" IN (SELECT "TaiKhoanID" FROM customer_accounts)
      AND n."TinNhanID" IN (
        SELECT m."TinNhanID"
        FROM public."TinNhan" AS m
        WHERE m."DonHangID" IS NOT DISTINCT FROM p_order_id
          AND m."NguoiNhanID" IN (SELECT "TaiKhoanID" FROM customer_accounts)
          AND (
            m."TrangThai" = 'Đã đọc'
            OR m."TinNhanID" IN (SELECT "TinNhanID" FROM updated)
          )
      )
    RETURNING n."ThongBaoID"
  )
  SELECT count(*)::integer FROM updated;
$function$;

REVOKE ALL ON FUNCTION public.mark_chat_thread_read(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_chat_thread_read(integer, integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
