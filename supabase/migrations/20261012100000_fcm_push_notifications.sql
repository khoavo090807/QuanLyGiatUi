CREATE TABLE IF NOT EXISTS public.push_device_tokens (
  token text PRIMARY KEY,
  "TaiKhoanID" integer NOT NULL REFERENCES public."TaiKhoan" ("TaiKhoanID") ON DELETE CASCADE,
  platform text NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.push_device_tokens FROM anon, authenticated;
GRANT ALL ON TABLE public.push_device_tokens TO service_role;

CREATE OR REPLACE FUNCTION public.register_push_device_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  account_id bigint;
BEGIN
  IF auth.uid() IS NULL OR p_token IS NULL OR length(p_token) < 20 THEN
    RAISE EXCEPTION 'A signed-in user and valid device token are required';
  END IF;

  account_id := private.current_account_id();
  IF account_id IS NULL THEN
    RAISE EXCEPTION 'No active application account is associated with this user';
  END IF;

  -- A device token belongs to one account at a time. Reassignment also cleans
  -- up tokens left behind by an interrupted sign-out.
  DELETE FROM public.push_device_tokens WHERE token = p_token;
  INSERT INTO public.push_device_tokens (token, "TaiKhoanID", platform, updated_at)
  VALUES (p_token, account_id::integer, 'android', now());
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_device_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  account_id bigint;
BEGIN
  IF auth.uid() IS NULL OR p_token IS NULL THEN
    RETURN;
  END IF;

  account_id := private.current_account_id();
  IF account_id IS NOT NULL THEN
    DELETE FROM public.push_device_tokens
    WHERE token = p_token AND "TaiKhoanID" = account_id::integer;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.register_push_device_token(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_device_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_device_token(text) TO authenticated;

-- The trigger stays dormant until the owner creates a Vault secret named
-- push_webhook_secret and configures the same value as an Edge Function secret.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION private.dispatch_push_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  webhook_secret text;
BEGIN
  SELECT decrypted_secret
  INTO webhook_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_webhook_secret'
  LIMIT 1;

  IF webhook_secret IS NULL OR webhook_secret = '' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://osnblefzulmsuthhuswl.supabase.co/functions/v1/push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-webhook-secret', webhook_secret
    ),
    body := jsonb_build_object('record', jsonb_build_object(
      'ThongBaoID', NEW."ThongBaoID",
      'TaiKhoanID', NEW."TaiKhoanID",
      'TieuDe', NEW."TieuDe",
      'NoiDung', NEW."NoiDung",
      'LoaiThongBao', NEW."LoaiThongBao",
      'DonHangID', NEW."DonHangID"
    ))
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.dispatch_push_notification() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS dispatch_push_notification_after_insert ON public."ThongBao";
CREATE TRIGGER dispatch_push_notification_after_insert
AFTER INSERT ON public."ThongBao"
FOR EACH ROW EXECUTE FUNCTION private.dispatch_push_notification();
