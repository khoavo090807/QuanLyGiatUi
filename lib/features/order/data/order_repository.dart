import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';

enum LaundryBookingStatus {
  awaitingReception('ChoTiepNhan', 'Chờ tiếp nhận'),
  confirmed('DaXacNhan', 'Đã xác nhận'),
  cancelled('DaHuy', 'Đã hủy'),
  completed('HoanThanh', 'Hoàn thành'),
  unknown('Unknown', 'Không xác định');

  const LaundryBookingStatus(this.databaseValue, this.displayValue);

  final String databaseValue;
  final String displayValue;

  static LaundryBookingStatus fromDatabase(String value) => values.firstWhere(
    (status) => status.databaseValue == value,
    orElse: () => switch (value) {
      'Chờ xác nhận' => awaitingReception,
      'Đã xác nhận' => confirmed,
      'Đã hủy' => cancelled,
      'Hoàn thành' => completed,
      _ => unknown,
    },
  );
}

class LaundryPriceOption {
  const LaundryPriceOption({
    required this.priceId,
    required this.serviceId,
    required this.serviceName,
    required this.itemTypeId,
    required this.itemTypeName,
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
    required this.unitPriceVnd,
  });

  final int priceId;
  final int serviceId;
  final String serviceName;
  final int itemTypeId;
  final String itemTypeName;
  final int unitId;
  final String unitName;
  final String unitSymbol;
  final num unitPriceVnd;

  factory LaundryPriceOption.fromJson(Map<String, dynamic> json) {
    return LaundryPriceOption(
      priceId: (json['banggiaid'] as num).toInt(),
      serviceId: (json['dichvuid'] as num).toInt(),
      serviceName: json['tendichvu'] as String,
      itemTypeId: (json['loaidogiatid'] as num).toInt(),
      itemTypeName: json['tenloaidogiat'] as String,
      unitId: (json['donvitinhid'] as num).toInt(),
      unitName: json['tendonvitinh'] as String,
      unitSymbol: json['kyhieu'] as String? ?? '',
      unitPriceVnd: json['dongia'] as num,
    );
  }
}

class CreatedLaundryBooking {
  const CreatedLaundryBooking({
    required this.bookingId,
    required this.bookingNumber,
    required this.estimatedTotalVnd,
    this.itemCount = 1,
  });

  final int bookingId;
  final String bookingNumber;
  final num estimatedTotalVnd;
  final int itemCount;

  factory CreatedLaundryBooking.fromJson(Map<String, dynamic> json) {
    return CreatedLaundryBooking(
      bookingId: (json['bookingid'] as num).toInt(),
      bookingNumber: json['mabooking'] as String,
      estimatedTotalVnd: json['thanhtien'] as num,
      itemCount: (json['itemcount'] as num?)?.toInt() ?? 1,
    );
  }
}

class LaundryOrderRecord {
  const LaundryOrderRecord({
    required this.orderId,
    this.bookingId,
    required this.orderNumber,
    required this.status,
    required this.totalVnd,
    required this.createdAt,
    required this.lineDescription,
    this.canCancelBooking = false,
    this.hasLaundryDetails = true,
  });

  final int? orderId;
  final int? bookingId;
  final String orderNumber;
  final String status;
  final num totalVnd;
  final DateTime createdAt;
  final String lineDescription;
  final bool canCancelBooking;
  final bool hasLaundryDetails;

  factory LaundryOrderRecord.fromJson(Map<String, dynamic> json) {
    final details = json['ChiTietDonHang'] as List<dynamic>? ?? const [];
    final descriptions = details.map((entry) {
      final detail = entry as Map<String, dynamic>;
      final service = detail['DichVu'] as Map<String, dynamic>?;
      final itemType = detail['LoaiDoGiat'] as Map<String, dynamic>?;
      final unit = detail['DonViTinh'] as Map<String, dynamic>?;
      final measurement = detail['KhoiLuong'] ?? detail['SoLuong'];
      return '${service?['TenDichVu'] ?? 'Dịch vụ'} · '
          '${itemType?['TenLoaiDoGiat'] ?? 'Đồ giặt'} · '
          '$measurement ${unit?['KyHieu'] ?? ''}';
    });

    return LaundryOrderRecord(
      orderId: (json['DonHangID'] as num).toInt(),
      bookingId: (json['BookingID'] as num?)?.toInt(),
      orderNumber: json['MaDonHang'] as String,
      status: json['TrangThai'] as String,
      totalVnd: json['ThanhTien'] as num,
      createdAt: DateTime.parse(json['NgayTao'] as String),
      lineDescription: descriptions.isEmpty
          ? 'Cửa hàng đang kiểm nhận đồ'
          : descriptions.join(', '),
    );
  }

  factory LaundryOrderRecord.fromBookingJson(Map<String, dynamic> json) {
    final details = json['ChiTietBooking'] as List<dynamic>? ?? const [];
    // Build descriptions from all items
    final descriptions = details.map((entry) {
      final detail = entry as Map<String, dynamic>;
      final service = detail['DichVu'] as Map<String, dynamic>?;
      final itemType = detail['LoaiDoGiat'] as Map<String, dynamic>?;
      final unit = detail['DonViTinh'] as Map<String, dynamic>?;
      final measurement = detail['KhoiLuong'] ?? detail['SoLuong'];
      return '${service?['TenDichVu'] ?? 'Dịch vụ'} · '
          '${itemType?['TenLoaiDoGiat'] ?? 'Đồ giặt'} · '
          '$measurement ${unit?['KyHieu'] ?? ''}';
    }).toList();

    final bookingStatus = LaundryBookingStatus.fromDatabase(
      json['TrangThai'] as String,
    );

    // Calculate total from all detail items
    final totalVnd = details.fold<num>(
      0,
      (sum, entry) =>
          sum + ((entry as Map<String, dynamic>)['ThanhTien'] as num? ?? 0),
    );

    return LaundryOrderRecord(
      orderId: null,
      bookingId: (json['BookingID'] as num).toInt(),
      orderNumber: json['MaBooking'] as String,
      status: bookingStatus.displayValue,
      totalVnd: totalVnd,
      createdAt: DateTime.parse(json['NgayTao'] as String),
      lineDescription: descriptions.isEmpty
          ? 'Cửa hàng sẽ kiểm nhận đồ và báo giá'
          : descriptions.join(', '),
      canCancelBooking: bookingStatus == LaundryBookingStatus.awaitingReception,
      hasLaundryDetails: details.isNotEmpty,
    );
  }
}

class LaundryOrderStatusEvent {
  const LaundryOrderStatusEvent({
    required this.previousStatus,
    required this.status,
    required this.note,
    required this.occurredAt,
  });

  final String? previousStatus;
  final String status;
  final String? note;
  final DateTime occurredAt;

  factory LaundryOrderStatusEvent.fromJson(Map<String, dynamic> json) {
    return LaundryOrderStatusEvent(
      previousStatus: json['trangthaicu'] as String?,
      status: json['trangthaimoi'] as String,
      note: json['lydo'] as String?,
      occurredAt: DateTime.parse(json['thoigian'] as String),
    );
  }
}

class LaundryOrderDetails {
  const LaundryOrderDetails({
    required this.order,
    required this.events,
    this.pickupMethod,
    this.address,
    this.appointment,
    this.notes,
    this.items,
  });

  final LaundryOrderRecord order;
  final List<LaundryOrderStatusEvent> events;
  final String? pickupMethod;
  final String? address;
  final DateTime? appointment;
  final String? notes;
  final List<LaundryOrderItem>? items;
}

class LaundryOrderItem {
  const LaundryOrderItem({
    required this.serviceName,
    required this.itemTypeName,
    required this.unitSymbol,
    required this.measurement,
    required this.unitPriceVnd,
    required this.totalVnd,
  });

  final String serviceName;
  final String itemTypeName;
  final String unitSymbol;
  final num measurement;
  final num unitPriceVnd;
  final num totalVnd;
}

class OrderRepository {
  OrderRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static String createIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Future<List<LaundryPriceOption>> getActivePrices() async {
    final rows = await _client
        .from('banggia')
        .select(
          'banggiaid,dichvuid,loaidogiatid,donvitinhid,dongia,'
          'dichvu!inner(tendichvu,trangthai),'
          'loaidogiat!inner(tenloaidogiat,trangthai),'
          'donvitinh!inner(tendonvitinh,kyhieu,trangthai)',
        )
        .eq('trangthai', 'Hoạt động')
        .order('banggiaid');

    return (rows as List<dynamic>)
        .map((row) {
          final price = row as Map<String, dynamic>;
          final service = price['dichvu'] as Map<String, dynamic>;
          final itemType = price['loaidogiat'] as Map<String, dynamic>;
          final unit = price['donvitinh'] as Map<String, dynamic>;

          return LaundryPriceOption.fromJson({
            ...price,
            'tendichvu': service['tendichvu'],
            'tenloaidogiat': itemType['tenloaidogiat'],
            'tendonvitinh': unit['tendonvitinh'],
            'kyhieu': unit['kyhieu'],
          });
        })
        .toList(growable: false);
  }

  Future<List<LaundryOrderRecord>> getCustomerOrders() async {
    final rows = await _client
        .from('DonHang')
        .select(
          'DonHangID,BookingID,MaDonHang,TrangThai,ThanhTien,NgayTao,'
          'ChiTietDonHang('
          'SoLuong,KhoiLuong,DichVu(TenDichVu),'
          'LoaiDoGiat(TenLoaiDoGiat),DonViTinh(KyHieu)'
          ')',
        )
        .order('NgayTao', ascending: false);

    return (rows as List<dynamic>)
        .map((row) => LaundryOrderRecord.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<LaundryOrderRecord>> getStaffOrders() => getCustomerOrders();

  Future<List<LaundryOrderRecord>> getCustomerHistory() async {
    final results = await Future.wait([getCustomerOrders(), _getBookings()]);
    final orders = results[0];
    final orderBookingIds = orders
        .map((order) => order.bookingId)
        .whereType<int>()
        .toSet();
    final bookings = results[1].where(
      (booking) => !orderBookingIds.contains(booking.bookingId),
    );
    return [...orders, ...bookings]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<LaundryOrderRecord>> getStaffQueue() async {
    final results = await Future.wait([getStaffOrders(), _getBookings()]);
    final pendingBookings = results[1].where(
      (booking) => booking.canCancelBooking,
    );
    return [...results[0], ...pendingBookings]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<LaundryOrderRecord>> _getBookings() async {
    // Get bookings first
    final bookings = await _client
        .from('Booking')
        .select('BookingID,MaBooking,TrangThai,NgayTao')
        .order('NgayTao', ascending: false);

    // Then fetch ChiTietBooking for each booking
    final bookingIds = (bookings as List<dynamic>)
        .map((b) => (b as Map<String, dynamic>)['BookingID'] as int)
        .toList();

    final chiTietMap = <int, List<dynamic>>{};
    if (bookingIds.isNotEmpty) {
      final chiTietRows = await _client
          .from('ChiTietBooking')
          .select(
            'BookingID,SoLuong,KhoiLuong,ThanhTien,'
            'DichVu(TenDichVu),LoaiDoGiat(TenLoaiDoGiat),DonViTinh(KyHieu)',
          )
          .inFilter('BookingID', bookingIds);

      for (final row in chiTietRows as List<dynamic>) {
        final detail = row as Map<String, dynamic>;
        final bookingId = (detail['BookingID'] as num).toInt();
        chiTietMap.putIfAbsent(bookingId, () => []).add(detail);
      }
    }

    // Build LaundryOrderRecord with joined data
    return (bookings as List<dynamic>)
        .map((row) {
          final booking = row as Map<String, dynamic>;
          final bookingId = (booking['BookingID'] as num).toInt();
          final details = chiTietMap[bookingId] ?? const [];
          return LaundryOrderRecord.fromBookingJson({
            ...booking,
            'ChiTietBooking': details,
          });
        })
        .toList(growable: false);
  }

  Future<void> transitionStatus({
    required int orderId,
    required String newStatus,
    String? reason,
  }) async {
    await _client.rpc(
      'transition_laundry_order',
      params: {
        'p_donhangid': orderId,
        'p_trangthaimoi': newStatus,
        'p_lydo': reason,
      },
    );
  }

  Future<void> confirmBooking(int bookingId, {required bool hasDetails}) async {
    await _client.rpc(
      hasDetails
          ? 'confirm_laundry_booking'
          : 'confirm_laundry_booking_without_details',
      params: {'p_bookingid': bookingId},
    );
  }

  Future<void> cancelBooking(int bookingId) async {
    await _client.rpc(
      'cancel_laundry_booking',
      params: {'p_bookingid': bookingId},
    );
  }

  Future<LaundryOrderDetails> getOrderDetails(int orderId) async {
    final order = await _client
        .from('DonHang')
        .select(
          'DonHangID,BookingID,MaDonHang,TrangThai,ThanhTien,NgayTao,'
          'ChiTietDonHang('
          'SoLuong,KhoiLuong,DonGia,ThanhTien,'
          'DichVu(TenDichVu),'
          'LoaiDoGiat(TenLoaiDoGiat),'
          'DonViTinh(KyHieu)'
          '),'
          'Booking(HinhThucNhanDo,DiaChiNhan,NgayHen,GioHen,GhiChu)',
        )
        .eq('DonHangID', orderId)
        .maybeSingle();

    if (order == null) throw StateError('Không tìm thấy đơn hàng.');

    final events = await _client
        .from('DonHang_TrangThai')
        .select('TrangThaiCu,TrangThaiMoi,LyDo,ThoiGian')
        .eq('DonHangID', orderId)
        .order('ThoiGian');

    final booking = order['Booking'] as Map<String, dynamic>?;
    DateTime? appointment;
    if (booking != null && booking['NgayHen'] != null && booking['GioHen'] != null) {
      final date = DateTime.parse(booking['NgayHen'] as String);
      final timeStr = booking['GioHen'] as String;
      final timeParts = timeStr.split(':');
      appointment = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    }

    final details = order['ChiTietDonHang'] as List<dynamic>? ?? [];
    final items = details.map((entry) {
      final detail = entry as Map<String, dynamic>;
      final service = detail['DichVu'] as Map<String, dynamic>?;
      final itemType = detail['LoaiDoGiat'] as Map<String, dynamic>?;
      final unit = detail['DonViTinh'] as Map<String, dynamic>?;
      final measurement = detail['KhoiLuong'] ?? detail['SoLuong'];
      final unitPrice = detail['DonGia'] as num? ?? 0;
      final total = detail['ThanhTien'] as num? ?? 0;
      return LaundryOrderItem(
        serviceName: service?['TenDichVu'] as String? ?? 'Dịch vụ',
        itemTypeName: itemType?['TenLoaiDoGiat'] as String? ?? 'Đồ giặt',
        unitSymbol: unit?['KyHieu'] as String? ?? '',
        measurement: measurement as num,
        unitPriceVnd: unitPrice,
        totalVnd: total,
      );
    }).toList(growable: false);

    return LaundryOrderDetails(
      order: LaundryOrderRecord.fromJson(order),
      events: (events as List<dynamic>)
          .map((event) => LaundryOrderStatusEvent.fromJson(event as Map<String, dynamic>))
          .toList(growable: false),
      pickupMethod: booking?['HinhThucNhanDo'] as String?,
      address: booking?['DiaChiNhan'] as String?,
      appointment: appointment,
      notes: booking?['GhiChu'] as String?,
      items: items.isNotEmpty ? items : null,
    );
  }



  Future<LaundryOrderDetails> getBookingDetails(int bookingId) async {
    final booking = await _client
        .from('Booking')
        .select(
          'BookingID,MaBooking,TrangThai,NgayTao,HinhThucNhanDo,DiaChiNhan,NgayHen,GioHen,GhiChu,'
          'ChiTietBooking('
          'SoLuong,KhoiLuong,DonGia,ThanhTien,'
          'DichVu(TenDichVu),'
          'LoaiDoGiat(TenLoaiDoGiat),'
          'DonViTinh(KyHieu)'
          ')',
        )
        .eq('BookingID', bookingId)
        .maybeSingle();

    if (booking == null) throw StateError('Không tìm thấy yêu cầu đặt giặt.');

    final record = LaundryOrderRecord.fromBookingJson(booking);
    
    DateTime? appointment;
    if (booking['NgayHen'] != null && booking['GioHen'] != null) {
      final date = DateTime.parse(booking['NgayHen'] as String);
      final timeStr = booking['GioHen'] as String;
      final timeParts = timeStr.split(':');
      appointment = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    }

    final details = booking['ChiTietBooking'] as List<dynamic>? ?? [];
    final items = details.map((entry) {
      final detail = entry as Map<String, dynamic>;
      final service = detail['DichVu'] as Map<String, dynamic>?;
      final itemType = detail['LoaiDoGiat'] as Map<String, dynamic>?;
      final unit = detail['DonViTinh'] as Map<String, dynamic>?;
      final measurement = detail['KhoiLuong'] ?? detail['SoLuong'];
      final unitPrice = detail['DonGia'] as num? ?? 0;
      final total = detail['ThanhTien'] as num? ?? 0;
      return LaundryOrderItem(
        serviceName: service?['TenDichVu'] as String? ?? 'Dịch vụ',
        itemTypeName: itemType?['TenLoaiDoGiat'] as String? ?? 'Đồ giặt',
        unitSymbol: unit?['KyHieu'] as String? ?? '',
        measurement: measurement as num,
        unitPriceVnd: unitPrice,
        totalVnd: total,
      );
    }).toList(growable: false);
    
    return LaundryOrderDetails(
      order: record,
      events: const [],
      pickupMethod: booking['HinhThucNhanDo'] as String?,
      address: booking['DiaChiNhan'] as String?,
      appointment: appointment,
      notes: booking['GhiChu'] as String?,
      items: items.isNotEmpty ? items : null,
    );
  }

  Future<CreatedLaundryBooking> submitOrder({
    required int priceId,
    required num measurement,
    required String pickupMethod,
    required String? address,
    required DateTime appointment,
    required String notes,
    required String idempotencyKey,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập trước khi đặt đơn.');
    }

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': user.userMetadata?['full_name']},
    );

    final result = await _client.rpc(
      'submit_laundry_order',
      params: {
        'p_banggiaid': priceId,
        'p_measurement': measurement,
        'p_hinhthucnhando': pickupMethod,
        'p_diachinhan': address,
        'p_ngayhen': _formatDate(appointment),
        'p_giohen': _formatTime(appointment),
        'p_ghichu': notes.trim().isEmpty ? null : notes.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );

    return CreatedLaundryBooking.fromJson(result as Map<String, dynamic>);
  }

  Future<CreatedLaundryBooking> submitCartOrder({
    required Iterable<CartItem> items,
    required String pickupMethod,
    required String? address,
    required DateTime appointment,
    required String notes,
    required String idempotencyKey,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập trước khi đặt đơn.');
    }

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': user.userMetadata?['full_name']},
    );

    final itemsJson = items.map((item) => item.toJson()).toList();

    final result = await _client.rpc(
      'submit_laundry_order_cart',
      params: {
        'p_items': itemsJson,
        'p_hinhthucnhando': pickupMethod,
        'p_diachinhan': address,
        'p_ngayhen': _formatDate(appointment),
        'p_giohen': _formatTime(appointment),
        'p_ghichu': notes.trim().isEmpty ? null : notes.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );

    return CreatedLaundryBooking.fromJson(result as Map<String, dynamic>);
  }

  Future<CreatedLaundryBooking> submitBookingWithoutDetails({
    required String pickupMethod,
    required String? address,
    required DateTime appointment,
    required String notes,
    required String idempotencyKey,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập trước khi đặt đơn.');
    }

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': user.userMetadata?['full_name']},
    );

    final result = await _client.rpc(
      'submit_laundry_booking_without_details',
      params: {
        'p_hinhthucnhando': pickupMethod,
        'p_diachinhan': address,
        'p_ngayhen': _formatDate(appointment),
        'p_giohen': _formatTime(appointment),
        'p_ghichu': notes.trim().isEmpty ? null : notes.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );

    return CreatedLaundryBooking.fromJson(result as Map<String, dynamic>);
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.year.toString().padLeft(4, '0')}-'
        '${localDate.month.toString().padLeft(2, '0')}-'
        '${localDate.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.hour.toString().padLeft(2, '0')}:'
        '${localDate.minute.toString().padLeft(2, '0')}:00';
  }
}
