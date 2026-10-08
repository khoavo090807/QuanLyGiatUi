BEGIN;

-- Prefer the account that submitted this booking. A customer can have more
-- than one active account, so resolving by customer ID alone can send the
-- notification to another login belonging to the same customer record.
CREATE OR REPLACE FUNCTION private.notify_booking_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_account_id bigint;
  customer_name text;
BEGIN
  customer_account_id := COALESCE(
    private.current_account_id(),
    private.account_id_for_customer(NEW."KhachHangID")
  );

  SELECT "HoTen"
  INTO customer_name
  FROM public."KhachHang"
  WHERE "KhachHangID" = NEW."KhachHangID";

  IF customer_account_id IS NOT NULL THEN
    INSERT INTO public."ThongBao" (
      "TaiKhoanID", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc", "DonHangID", "LoaiThongBao"
    )
    SELECT
      customer_account_id::integer,
      'Yêu cầu đặt giặt đã gửi'::varchar,
      ('Yêu cầu ' || NEW."MaBooking" || ' đã được gửi. Cửa hàng sẽ tiếp nhận trong thời gian sớm nhất.')::varchar,
      now()::timestamp,
      false,
      NULL::integer,
      'order_created'::varchar
    WHERE NOT EXISTS (
      SELECT 1
      FROM public."ThongBao" AS notification
      WHERE notification."TaiKhoanID" = customer_account_id
        AND notification."LoaiThongBao" = 'order_created'
        AND notification."DonHangID" IS NULL
        AND notification."NoiDung" LIKE '%' || NEW."MaBooking" || '%'
    );
  END IF;

  PERFORM public.notify_staff_new_booking(
    NEW."BookingID",
    NEW."MaBooking",
    customer_name
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(
  p_notification_ids bigint[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  current_account_id bigint := (SELECT private.current_account_id());
  updated_count integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR current_account_id IS NULL THEN
    RAISE EXCEPTION 'An active account is required';
  END IF;

  UPDATE public."ThongBao"
  SET "DaDoc" = true
  WHERE "TaiKhoanID" = current_account_id
    AND "DaDoc" = false
    AND (
      p_notification_ids IS NULL
      OR "ThongBaoID" = ANY (p_notification_ids)
    );

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_notifications_read(bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(bigint[]) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
