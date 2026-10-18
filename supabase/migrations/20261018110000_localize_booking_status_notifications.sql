BEGIN;

CREATE OR REPLACE FUNCTION private.notify_customer_booking_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_account_id bigint;
  notification_title varchar(200);
  notification_body varchar(1000);
  notification_type varchar(50);
  status_label text;
BEGIN
  customer_account_id := private.account_id_for_booking(NEW."BookingID", NEW."KhachHangID");

  IF customer_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  status_label := CASE NEW."TrangThai"
    WHEN 'ChoTiepNhan' THEN 'Chờ tiếp nhận'
    WHEN 'DaXacNhan' THEN 'Đã xác nhận'
    WHEN 'DaHuy' THEN 'Đã hủy'
    WHEN 'HoanThanh' THEN 'Hoàn thành'
    ELSE NEW."TrangThai"
  END;

  IF NEW."TrangThai" IN ('DaHuy', 'Đã hủy') THEN
    notification_title := 'Đặt lịch đã được hủy';
    notification_body := ('Đặt lịch ' || NEW."MaBooking" || ' đã được hủy.');
    notification_type := 'booking_cancelled';
  ELSIF NEW."TrangThai" IS DISTINCT FROM OLD."TrangThai" THEN
    notification_title := 'Đặt lịch đã được cập nhật';
    notification_body := ('Đặt lịch ' || NEW."MaBooking" || ' đã chuyển sang trạng thái ' || status_label || '.');
    notification_type := 'booking_status_updated';
  ELSE
    notification_title := 'Cửa hàng đã kiểm tra đặt lịch';
    notification_body := ('Thông tin và số lượng thực tế của đặt lịch ' || NEW."MaBooking" || ' đã được cập nhật.');
    notification_type := 'booking_updated';
  END IF;

  INSERT INTO public."ThongBao" (
    "TaiKhoanID", "DonHangID", "BookingID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
  ) VALUES (
    customer_account_id::integer, NULL, NEW."BookingID", notification_type, notification_title,
    notification_body, now()::timestamp, false
  );

  RETURN NEW;
END;
$$;

COMMIT;
