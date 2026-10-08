ALTER TABLE public."ThongBao"
  ADD COLUMN IF NOT EXISTS "TinNhanID" integer;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public."ThongBao"'::regclass
      AND conname = 'ThongBao_TinNhanID_fkey'
  ) THEN
    ALTER TABLE public."ThongBao"
      ADD CONSTRAINT "ThongBao_TinNhanID_fkey"
      FOREIGN KEY ("TinNhanID") REFERENCES public."TinNhan"("TinNhanID") ON DELETE SET NULL;
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
       "TinNhanID" AS tinnhanid
FROM public."ThongBao";

CREATE OR REPLACE FUNCTION public.notify_customer_of_store_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  sender_is_staff boolean;
  recipient_is_customer boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public."TaiKhoan" a
    JOIN public."TaiKhoan_VaiTro" av ON av."TaiKhoanID" = a."TaiKhoanID"
    JOIN public."VaiTro" r ON r."VaiTroID" = av."VaiTroID"
    WHERE a."TaiKhoanID" = NEW."NguoiGuiID"
      AND a."NhanVienID" IS NOT NULL
      AND a."TrangThai" = 'Hoạt động'
      AND r."TrangThai" = 'Hoạt động'
      AND (r."TenVaiTro" IN ('Nhân viên', 'Chủ cửa hàng') OR r."TenVaiTro" LIKE 'Quản lý%')
  ) INTO sender_is_staff;

  SELECT EXISTS (
    SELECT 1 FROM public."TaiKhoan" a
    WHERE a."TaiKhoanID" = NEW."NguoiNhanID" AND a."KhachHangID" IS NOT NULL
  ) INTO recipient_is_customer;

  IF sender_is_staff AND recipient_is_customer THEN
    INSERT INTO public."ThongBao" (
      "TaiKhoanID", "DonHangID", "TinNhanID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
    ) VALUES (
      NEW."NguoiNhanID", NEW."DonHangID", NEW."TinNhanID", 'new_message',
      'Tin nhắn mới từ cửa hàng',
      left('Cửa hàng: ' || NEW."NoiDung", 1000),
      timezone('utc', now())::timestamp, false
    );
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS notify_customer_of_store_message ON public."TinNhan";
CREATE TRIGGER notify_customer_of_store_message
AFTER INSERT ON public."TinNhan"
FOR EACH ROW EXECUTE FUNCTION public.notify_customer_of_store_message();

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ThongBao'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."ThongBao";
  END IF;
END
$migration$;

NOTIFY pgrst, 'reload schema';
