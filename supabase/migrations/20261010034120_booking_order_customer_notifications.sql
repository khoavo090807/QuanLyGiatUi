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
BEGIN
  customer_account_id := private.account_id_for_customer(NEW."KhachHangID");

  IF customer_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW."TrangThai" = 'DaHuy' THEN
    notification_title := 'Đặt lịch đã được hủy';
    notification_body := ('Đặt lịch ' || NEW."MaBooking" || ' đã được hủy.');
    notification_type := 'booking_cancelled';
  ELSIF NEW."TrangThai" IS DISTINCT FROM OLD."TrangThai" THEN
    notification_title := 'Đặt lịch đã được cập nhật';
    notification_body := ('Đặt lịch ' || NEW."MaBooking" || ' đã chuyển sang trạng thái ' || NEW."TrangThai" || '.');
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

CREATE OR REPLACE FUNCTION private.notify_customer_booking_deleted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  customer_account_id bigint;
BEGIN
  customer_account_id := private.account_id_for_customer(OLD."KhachHangID");

  IF customer_account_id IS NOT NULL THEN
    INSERT INTO public."ThongBao" (
      "TaiKhoanID", "DonHangID", "BookingID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
    ) VALUES (
      customer_account_id::integer, NULL, OLD."BookingID", 'booking_cancelled', 'Đặt lịch đã được hủy',
      ('Đặt lịch ' || OLD."MaBooking" || ' đã được hủy.'), now()::timestamp, false
    );
  END IF;

  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION private.notify_customer_order_changed()
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
BEGIN
  customer_account_id := private.account_id_for_customer(NEW."KhachHangID");

  IF customer_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    notification_title := 'Đơn hàng đã được tạo';
    notification_body := ('Cửa hàng đã tiếp nhận đồ và tạo đơn ' || NEW."MaDonHang" || '.');
    notification_type := 'order_created';
  ELSIF NEW."TrangThai" = 'Đã hủy' AND NEW."TrangThai" IS DISTINCT FROM OLD."TrangThai" THEN
    notification_title := 'Đơn hàng đã được hủy';
    notification_body := ('Đơn hàng ' || NEW."MaDonHang" || ' đã được hủy.');
    notification_type := 'order_cancelled';
  ELSIF NEW."TrangThai" IS DISTINCT FROM OLD."TrangThai" THEN
    notification_title := 'Đơn hàng đã cập nhật trạng thái';
    notification_body := ('Đơn hàng ' || NEW."MaDonHang" || ' hiện ở trạng thái ' || NEW."TrangThai" || '.');
    notification_type := 'order_status_updated';
  ELSE
    notification_title := 'Đơn hàng đã được cập nhật';
    notification_body := ('Thông tin đơn hàng ' || NEW."MaDonHang" || ' đã được cửa hàng cập nhật.');
    notification_type := 'order_updated';
  END IF;

  INSERT INTO public."ThongBao" (
    "TaiKhoanID", "DonHangID", "BookingID", "LoaiThongBao", "TieuDe", "NoiDung", "ThoiGianGui", "DaDoc"
  ) VALUES (
    customer_account_id::integer, NEW."DonHangID", NEW."BookingID", notification_type,
    notification_title, notification_body, now()::timestamp, false
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_customer_booking_changed ON public."Booking";
CREATE TRIGGER notify_customer_booking_changed
  AFTER UPDATE ON public."Booking"
  FOR EACH ROW
  WHEN (OLD.* IS DISTINCT FROM NEW.*)
  EXECUTE FUNCTION private.notify_customer_booking_changed();

DROP TRIGGER IF EXISTS notify_customer_booking_deleted ON public."Booking";
CREATE TRIGGER notify_customer_booking_deleted
  AFTER DELETE ON public."Booking"
  FOR EACH ROW
  EXECUTE FUNCTION private.notify_customer_booking_deleted();

DROP TRIGGER IF EXISTS notify_customer_order_changed ON public."DonHang";
CREATE TRIGGER notify_customer_order_changed
  AFTER INSERT OR UPDATE ON public."DonHang"
  FOR EACH ROW
  EXECUTE FUNCTION private.notify_customer_order_changed();

REVOKE ALL ON FUNCTION private.notify_customer_booking_changed() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.notify_customer_booking_deleted() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.notify_customer_order_changed() FROM PUBLIC;

COMMENT ON FUNCTION private.notify_customer_booking_changed() IS
  'Thông báo cho khách khi nhân viên web cập nhật hoặc hủy Booking.';
COMMENT ON FUNCTION private.notify_customer_order_changed() IS
  'Thông báo cho khách khi nhân viên web tạo, sửa hoặc đổi trạng thái Đơn hàng.';

COMMIT;
