import 'package:flutter_test/flutter_test.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';

void main() {
  test('parses the Booking payload returned by submit_laundry_order', () {
    final booking = CreatedLaundryBooking.fromJson({
      'bookingid': 11,
      'mabooking': 'BK-20260929122336-17194d74',
      'trangthai': 'ChoTiepNhan',
      'thanhtien': 10000,
    });

    expect(booking.bookingId, 11);
    expect(booking.bookingNumber, 'BK-20260929122336-17194d74');
    expect(booking.estimatedTotalVnd, 10000);
  });

  test('parses status-history RPC rows without changing event fields', () {
    final event = LaundryOrderStatusEvent.fromJson({
      'trangthaicu': 'Chờ tiếp nhận',
      'trangthaimoi': 'Đã tiếp nhận',
      'lydo': 'Đơn đã được cửa hàng xác nhận',
      'thoigian': '2026-10-03T07:00:00',
    });

    expect(event.previousStatus, 'Chờ tiếp nhận');
    expect(event.status, 'Đã tiếp nhận');
    expect(event.note, 'Đơn đã được cửa hàng xác nhận');
    expect(event.occurredAt, DateTime(2026, 10, 3, 7));
  });
}
