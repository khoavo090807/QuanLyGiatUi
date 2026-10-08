ALTER TABLE public."ThongBao"
  ADD COLUMN IF NOT EXISTS "BookingID" integer;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public."ThongBao"'::regclass
      AND conname = 'ThongBao_BookingID_fkey'
  ) THEN
    ALTER TABLE public."ThongBao"
      ADD CONSTRAINT "ThongBao_BookingID_fkey"
      FOREIGN KEY ("BookingID") REFERENCES public."Booking"("BookingID") ON DELETE SET NULL;
  END IF;
END
$migration$;

CREATE OR REPLACE VIEW public.thongbao WITH (security_invoker = true) AS
SELECT "ThongBaoID" AS thongbaoid,
       "TaiKhoanID" AS taikhoanid,
       "DonHangID" AS donhangid,
       "LoaiThongBao" AS loaithongbao,
       "TieuDe" AS tieude,
       "NoiDung" AS noidung,
       "ThoiGianGui" AS thoigiangui,
       "DaDoc" AS dadoc,
       "TinNhanID" AS tinnhanid,
       "BookingID" AS bookingid
FROM public."ThongBao";

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
      "TaiKhoanID", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc",
      "DonHangID", "BookingID", "LoaiThongBao"
    )
    SELECT
      customer_account_id::integer,
      'Yêu cầu đặt giặt đã gửi'::varchar,
      ('Yêu cầu ' || NEW."MaBooking" || ' đã được gửi. Cửa hàng sẽ tiếp nhận trong thời gian sớm nhất.')::varchar,
      now()::timestamp,
      false,
      NULL::integer,
      NEW."BookingID",
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

NOTIFY pgrst, 'reload schema';
