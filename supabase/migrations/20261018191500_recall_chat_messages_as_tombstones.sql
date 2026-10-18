BEGIN;

ALTER TABLE public."TinNhan"
  ADD COLUMN IF NOT EXISTS "DaThuHoi" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.recall_chat_message(p_message_id integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  recalled_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;

  UPDATE public."TinNhan" AS message
  SET "DaThuHoi" = true,
      "NoiDung" = 'Tin nhắn đã thu hồi',
      "NoiDungMaHoa" = NULL,
      "NoiDungNonce" = NULL,
      "MaHoaPhienBan" = NULL
  WHERE message."TinNhanID" = p_message_id
    AND message."NguoiGuiID" = private.current_account_id()
    AND message."DaThuHoi" = false;

  GET DIAGNOSTICS recalled_count = ROW_COUNT;
  RETURN recalled_count = 1;
END
$function$;

REVOKE ALL ON FUNCTION public.recall_chat_message(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recall_chat_message(integer) TO authenticated;

COMMIT;