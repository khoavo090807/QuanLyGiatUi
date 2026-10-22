CREATE OR REPLACE FUNCTION public.customer_email_exists(p_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.taikhoan AS account
    JOIN auth.users AS auth_user ON auth_user.id = account.userauthid
    WHERE account.khachhangid IS NOT NULL
      AND account.trangthai = 'Hoạt động'
      AND lower(btrim(account.email)) = lower(btrim(p_email))
      AND lower(auth_user.email) = lower(btrim(p_email))
  );
$$;

REVOKE ALL ON FUNCTION public.customer_email_exists(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_email_exists(text) TO anon, authenticated;
