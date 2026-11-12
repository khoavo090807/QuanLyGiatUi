BEGIN;

CREATE OR REPLACE FUNCTION public.update_customer_profile(
  p_full_name text,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_id bigint := (SELECT private.current_customer_id());
  account_id bigint;
  phone_value text;
BEGIN
  IF customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF nullif(btrim(p_full_name), '') IS NULL THEN
    RAISE EXCEPTION 'Full name is required';
  END IF;

  phone_value := regexp_replace(coalesce(btrim(p_phone), ''), '[[:space:]().-]', '', 'g');
  IF phone_value ~ '^\+84(3[2-9]|5[25689]|7[0-9]|8[1-9]|9[0-9])[0-9]{7}$' THEN
    phone_value := '0' || substring(phone_value FROM 4);
  ELSIF phone_value ~ '^84(3[2-9]|5[25689]|7[0-9]|8[1-9]|9[0-9])[0-9]{7}$' THEN
    phone_value := '0' || substring(phone_value FROM 3);
  END IF;

  IF phone_value !~ '^0(3[2-9]|5[25689]|7[0-9]|8[1-9]|9[0-9])[0-9]{7}$' THEN
    RAISE EXCEPTION 'A valid Vietnamese mobile number is required';
  END IF;

  SELECT "TaiKhoanID"
  INTO account_id
  FROM public."TaiKhoan"
  WHERE "KhachHangID" = customer_id
    AND "UserAuthId" = (SELECT auth.uid())
  LIMIT 1;

  UPDATE public."KhachHang"
  SET "HoTen" = left(btrim(p_full_name), 150),
      "Email" = nullif(left(btrim(p_email), 255), ''),
      "SoDienThoai" = phone_value,
      "DiaChi" = nullif(left(btrim(p_address), 255), '')
  WHERE "KhachHangID" = customer_id;

  UPDATE public."TaiKhoan"
  SET "Email" = nullif(left(btrim(p_email), 255), ''),
      "SoDienThoai" = phone_value
  WHERE "TaiKhoanID" = account_id;

  RETURN jsonb_build_object('khachhangid', customer_id, 'taikhoanid', account_id);
END;
$$;

REVOKE ALL ON FUNCTION public.update_customer_profile(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_customer_profile(text, text, text, text) TO authenticated;

COMMIT;
