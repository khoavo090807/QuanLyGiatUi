BEGIN;

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
    SELECT 1
    FROM public."TinNhan" AS message
    WHERE message."TinNhanID" = p_message_id
      AND (
        message."NguoiGuiID" = account_id
        OR message."NguoiNhanID" = account_id
        OR (
          message."DonHangID" IS NOT NULL
          AND private.can_access_order(message."DonHangID"::bigint)
        )
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

COMMIT;