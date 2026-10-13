-- App-layer encryption for chat messages. AES-GCM keys are held in Supabase Vault
-- and are exposed only to the Edge Function's service role.
ALTER TABLE public."TinNhan"
  ADD COLUMN IF NOT EXISTS "NoiDungMaHoa" text,
  ADD COLUMN IF NOT EXISTS "NoiDungNonce" text,
  ADD COLUMN IF NOT EXISTS "MaHoaPhienBan" smallint;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'chat_message_aes_key'
  ) THEN
    PERFORM vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'base64'),
      'chat_message_aes_key',
      'AES-256-GCM key for chat-encryption Edge Function'
    );
  END IF;
END
$migration$;

CREATE OR REPLACE FUNCTION public.get_chat_encryption_key()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'service_role'
    THEN (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'chat_message_aes_key'
      LIMIT 1
    )
    ELSE NULL
  END;
$function$;
REVOKE ALL ON FUNCTION public.get_chat_encryption_key() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_chat_encryption_key() TO service_role;

CREATE OR REPLACE FUNCTION public.send_chat_message_encrypted(
  p_recipient_account_id integer,
  p_ciphertext text,
  p_nonce text,
  p_order_id integer DEFAULT NULL
)
RETURNS SETOF public."TinNhan"
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
  INSERT INTO public."TinNhan" (
    "NguoiGuiID", "NguoiNhanID", "DonHangID", "NoiDung", "ThoiGianGui", "TrangThai",
    "NoiDungMaHoa", "NoiDungNonce", "MaHoaPhienBan"
  )
  SELECT sender."TaiKhoanID", recipient."TaiKhoanID", p_order_id, '',
    timezone('utc', now())::timestamp, 'Đã gửi', p_ciphertext, p_nonce, 1
  FROM public."TaiKhoan" AS sender
  JOIN public."TaiKhoan" AS recipient ON recipient."TaiKhoanID" = p_recipient_account_id
  WHERE auth.uid() IS NOT NULL
    AND sender."TaiKhoanID" = private.current_account_id()
    AND sender."TrangThai" = 'Hoạt động'
    AND recipient."TrangThai" = 'Hoạt động'
    AND p_ciphertext IS NOT NULL AND char_length(p_ciphertext) BETWEEN 1 AND 12000
    AND p_nonce IS NOT NULL AND char_length(p_nonce) = 16
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
REVOKE ALL ON FUNCTION public.send_chat_message_encrypted(integer, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_chat_message_encrypted(integer, text, text, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.send_chat_message(integer, text, integer) FROM authenticated;

CREATE OR REPLACE FUNCTION public.migrate_chat_message_encrypted(
  p_message_id integer,
  p_ciphertext text,
  p_nonce text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  changed integer;
BEGIN
  IF auth.uid() IS NULL OR p_ciphertext IS NULL OR char_length(p_ciphertext) NOT BETWEEN 1 AND 12000
     OR p_nonce IS NULL OR char_length(p_nonce) <> 16 THEN
    RETURN false;
  END IF;

  UPDATE public."TinNhan" AS m
  SET "NoiDung" = '', "NoiDungMaHoa" = p_ciphertext,
      "NoiDungNonce" = p_nonce, "MaHoaPhienBan" = 1
  WHERE m."TinNhanID" = p_message_id
    AND m."NoiDungMaHoa" IS NULL
    AND (
      private.current_account_id() IN (m."NguoiGuiID", m."NguoiNhanID")
      OR EXISTS (
        SELECT 1
        FROM public."TaiKhoan" AS participant
        JOIN public."TaiKhoan" AS current_account
          ON current_account."TaiKhoanID" = private.current_account_id()
        WHERE participant."TaiKhoanID" IN (m."NguoiGuiID", m."NguoiNhanID")
          AND current_account."KhachHangID" IS NOT NULL
          AND participant."KhachHangID" = current_account."KhachHangID"
      )
      OR (m."DonHangID" IS NOT NULL AND private.is_messaging_staff()
          AND private.can_access_order(m."DonHangID"::bigint))
    );
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END
$function$;
REVOKE ALL ON FUNCTION public.migrate_chat_message_encrypted(integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.migrate_chat_message_encrypted(integer, text, text) TO authenticated;

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
  SELECT a."KhachHangID" INTO recipient_customer_id
  FROM public."TaiKhoan" AS a
  WHERE a."TaiKhoanID" = NEW."NguoiNhanID" AND a."TrangThai" = 'Hoạt động';

  SELECT EXISTS (
    SELECT 1 FROM public."TaiKhoan" AS a
    JOIN public."TaiKhoan_VaiTro" AS av ON av."TaiKhoanID" = a."TaiKhoanID"
    JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
    WHERE a."TaiKhoanID" = NEW."NguoiGuiID" AND a."NhanVienID" IS NOT NULL
      AND a."TrangThai" = 'Hoạt động' AND r."TrangThai" = 'Hoạt động'
      AND (r."TenVaiTro" IN ('Nhân viên', 'Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
  ) INTO sender_is_staff;

  IF recipient_customer_id IS NOT NULL THEN
    INSERT INTO public."ThongBao" (
      "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
    )
    SELECT customer_account."TaiKhoanID", NEW."DonHangID", NEW."TinNhanID", 'new_message',
      CASE WHEN sender_is_staff THEN 'Tin nhắn mới từ cửa hàng' ELSE 'Tin nhắn mới' END,
      'Bạn có tin nhắn mới.', timezone('utc', now())::timestamp, false
    FROM public."TaiKhoan" AS customer_account
    WHERE customer_account."KhachHangID" = recipient_customer_id
      AND customer_account."TrangThai" = 'Hoạt động'
      AND customer_account."TaiKhoanID" <> NEW."NguoiGuiID"
      AND (NEW."DonHangID" IS NULL OR EXISTS (
        SELECT 1 FROM public."DonHang" AS d
        WHERE d."DonHangID" = NEW."DonHangID" AND d."KhachHangID" = recipient_customer_id
      ))
      AND NOT EXISTS (
        SELECT 1 FROM public."ThongBao" AS existing
        WHERE existing."TaiKhoanID" = customer_account."TaiKhoanID"
          AND existing."TinNhanID" = NEW."TinNhanID" AND existing."LoaiThongBao" = 'new_message'
      );
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public."TaiKhoan" AS a
      JOIN public."TaiKhoan_VaiTro" AS av ON av."TaiKhoanID" = a."TaiKhoanID"
      JOIN public."VaiTro" AS r ON r."VaiTroID" = av."VaiTroID"
      WHERE a."TaiKhoanID" = NEW."NguoiNhanID" AND a."NhanVienID" IS NOT NULL
        AND a."TrangThai" = 'Hoạt động' AND r."TrangThai" = 'Hoạt động'
        AND (r."TenVaiTro" IN ('Nhân viên', 'Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
    ) INTO recipient_is_staff;
    IF recipient_is_staff THEN
      INSERT INTO public."ThongBao" (
        "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
      ) VALUES (
        NEW."NguoiNhanID", NEW."DonHangID", NEW."TinNhanID", 'new_message',
        'Tin nhắn mới từ khách hàng', 'Bạn có tin nhắn mới.', timezone('utc', now())::timestamp, false
      );
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

-- Remove previously copied message text from in-app and push notification rows.
UPDATE public."ThongBao"
SET "NoiDung" = 'Bạn có tin nhắn mới.'
WHERE "LoaiThongBao" = 'new_message';

-- Inbox previews must never return plaintext message content.
CREATE OR REPLACE FUNCTION public.get_staff_chat_inbox()
RETURNS TABLE (
  customer_account_id integer, customer_name text, customer_avatar_url text,
  order_id integer, order_number text, last_message text,
  last_message_at timestamp without time zone, last_sender_account_id integer, unread_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  WITH conversations AS (
    SELECT DISTINCT ON (
      CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END,
      m."DonHangID"
    )
      CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END AS customer_account_id,
      m."DonHangID" AS order_id, m."ThoiGianGui" AS last_message_at,
      m."NguoiGuiID" AS last_sender_account_id
    FROM public."TinNhan" AS m
    JOIN public."TaiKhoan" AS sender ON sender."TaiKhoanID" = m."NguoiGuiID"
    JOIN public."TaiKhoan" AS recipient ON recipient."TaiKhoanID" = m."NguoiNhanID"
    WHERE sender."KhachHangID" IS NOT NULL OR recipient."KhachHangID" IS NOT NULL
    ORDER BY CASE WHEN sender."KhachHangID" IS NOT NULL THEN sender."TaiKhoanID" ELSE recipient."TaiKhoanID" END,
      m."DonHangID", m."ThoiGianGui" DESC, m."TinNhanID" DESC
  )
  SELECT c.customer_account_id,
    coalesce(k."HoTen", a."TenDangNhap", 'Khách hàng')::text,
    coalesce(k."AvatarUrl", a."AvatarURL")::text,
    c.order_id, d."MaDonHang"::text, 'Bạn có tin nhắn mới.'::text,
    c.last_message_at, c.last_sender_account_id,
    (SELECT count(*) FROM public."TinNhan" AS m
      JOIN public."TaiKhoan" AS sender ON sender."TaiKhoanID" = m."NguoiGuiID"
      WHERE sender."KhachHangID" IS NOT NULL AND m."NguoiGuiID" = c.customer_account_id
        AND m."DonHangID" IS NOT DISTINCT FROM c.order_id
        AND m."TrangThai" IN ('Đã gửi', 'Đã nhận'))
  FROM conversations AS c
  JOIN public."TaiKhoan" AS a ON a."TaiKhoanID" = c.customer_account_id
  LEFT JOIN public."KhachHang" AS k ON k."KhachHangID" = a."KhachHangID"
  LEFT JOIN public."DonHang" AS d ON d."DonHangID" = c.order_id
  WHERE auth.uid() IS NOT NULL AND private.is_messaging_staff()
  ORDER BY c.last_message_at DESC;
$function$;
REVOKE ALL ON FUNCTION public.get_staff_chat_inbox() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_staff_chat_inbox() TO authenticated;

NOTIFY pgrst, 'reload schema';
