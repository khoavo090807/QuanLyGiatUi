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
}