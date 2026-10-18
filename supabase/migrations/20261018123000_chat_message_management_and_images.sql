BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-images',
  'chat-images',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE IF NOT EXISTS public."TinNhanAn" (
  "TaiKhoanID" integer NOT NULL REFERENCES public."TaiKhoan"("TaiKhoanID") ON DELETE CASCADE,
  "TinNhanID" integer NOT NULL REFERENCES public."TinNhan"("TinNhanID") ON DELETE CASCADE,
  "ThoiGianAn" timestamp without time zone NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY ("TaiKhoanID", "TinNhanID")
);

ALTER TABLE public."TinNhanAn" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public."TinNhanAn" FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public."TinNhanAn" TO service_role;

CREATE OR REPLACE FUNCTION public.hide_chat_message(p_message_id integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  account_id integer;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  account_id := private.current_account_id();
  IF account_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public."TinNhan" AS message
    WHERE message."TinNhanID" = p_message_id
      AND (
        message."NguoiGuiID" = account_id
        OR message."NguoiNhanID" = account_id
        OR (message."DonHangID" IS NOT NULL
          AND private.is_messaging_staff()
          AND private.can_access_order(message."DonHangID"::bigint))
      )
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public."TinNhanAn" ("TaiKhoanID", "TinNhanID")
  VALUES (account_id, p_message_id)
  ON CONFLICT DO NOTHING;
  RETURN true;
END
$function$;
REVOKE ALL ON FUNCTION public.hide_chat_message(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hide_chat_message(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_hidden_chat_message_ids(
  p_peer_account_id integer,
  p_order_id integer DEFAULT NULL
)
RETURNS TABLE ("TinNhanID" integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT hidden."TinNhanID"
  FROM public."TinNhanAn" AS hidden
  JOIN public."TinNhan" AS message ON message."TinNhanID" = hidden."TinNhanID"
  WHERE auth.uid() IS NOT NULL
    AND hidden."TaiKhoanID" = private.current_account_id()
    AND message."DonHangID" IS NOT DISTINCT FROM p_order_id
    AND (
      p_order_id IS NOT NULL
      OR message."NguoiGuiID" = p_peer_account_id
      OR message."NguoiNhanID" = p_peer_account_id
    );
$function$;
REVOKE ALL ON FUNCTION public.get_hidden_chat_message_ids(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_hidden_chat_message_ids(integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.recall_chat_message(p_message_id integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  deleted_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;

  DELETE FROM public."TinNhan" AS message
  WHERE message."TinNhanID" = p_message_id
    AND message."NguoiGuiID" = private.current_account_id();
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count = 1;
END
$function$;
REVOKE ALL ON FUNCTION public.recall_chat_message(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recall_chat_message(integer) TO authenticated;

COMMIT;
