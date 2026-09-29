import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final int bookingId;
  final String bookingNumber;
  final num estimatedTotalVnd;

  factory CreatedLaundryBooking.fromJson(Map<String, dynamic> json) {
    return CreatedLaundryBooking(
      bookingId: (json['bookingid'] as num).toInt(),
      bookingNumber: json['mabooking'] as String,
      estimatedTotalVnd: json['thanhtien'] as num,
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
  });

  final int? orderId;
  final int? bookingId;
  final String orderNumber;
  final String status;
  final num totalVnd;
  final DateTime createdAt;
  final String lineDescription;
  final bool canCancelBooking;

  factory LaundryOrderRecord.fromJson(Map<String, dynamic> json) {
    final details = json['chitietdonhang'] as List<dynamic>? ?? const [];
    final descriptions = details.map((entry) {
      final detail = entry as Map<String, dynamic>;
      final service = detail['dichvu'] as Map<String, dynamic>?;
      final itemType = detail['loaidogiat'] as Map<String, dynamic>?;
      final unit = detail['donvitinh'] as Map<String, dynamic>?;
      final measurement = detail['khoiluong'] ?? detail['soluong'];
      return '${service?['tendichvu'] ?? 'Dịch vụ'} · '
          '${itemType?['tenloaidogiat'] ?? 'Đồ giặt'} · '
          '$measurement ${unit?['kyhieu'] ?? ''}';
    });

    return LaundryOrderRecord(
      orderId: (json['donhangid'] as num).toInt(),
      bookingId: (json['bookingid'] as num?)?.toInt(),
      orderNumber: json['madonhang'] as String,
      status: json['trangthai'] as String,
      totalVnd: json['thanhtien'] as num,
      createdAt: DateTime.parse(json['ngaytao'] as String),
      lineDescription: descriptions.join(', '),
    );
  }

  factory LaundryOrderRecord.fromBookingJson(Map<String, dynamic> json) {
    final service = json['dichvu'] as Map<String, dynamic>?;
    final itemType = json['loaidogiat'] as Map<String, dynamic>?;
    final unit = json['donvitinh'] as Map<String, dynamic>?;
    final measurement = json['khoiluong'] ?? json['soluong'];
    final bookingStatus = LaundryBookingStatus.fromDatabase(
      json['trangthai'] as String,
    );

    return LaundryOrderRecord(
      orderId: null,
      bookingId: (json['bookingid'] as num).toInt(),
      orderNumber: json['mabooking'] as String,
      status: bookingStatus.displayValue,
      totalVnd: json['thanhtien'] as num? ?? 0,
      createdAt: DateTime.parse(json['ngaytao'] as String),
      lineDescription: measurement == null
          ? 'Chưa có chi tiết dịch vụ'
          : '${service?['tendichvu'] ?? 'Dịch vụ'} · '
                '${itemType?['tenloaidogiat'] ?? 'Đồ giặt'} · '
                '$measurement ${unit?['kyhieu'] ?? ''}',
      canCancelBooking: bookingStatus == LaundryBookingStatus.awaitingReception,
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
  const LaundryOrderDetails({required this.order, required this.events});

  final LaundryOrderRecord order;
  final List<LaundryOrderStatusEvent> events;
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
        .from('donhang')
        .select(
          'donhangid,bookingid,madonhang,trangthai,thanhtien,ngaytao,'
          'chitietdonhang('
          'soluong,khoiluong,dichvu(tendichvu),'
          'loaidogiat(tenloaidogiat),donvitinh(kyhieu)'
          ')',
        )
        .order('ngaytao', ascending: false);

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
    final rows = await _client
        .from('booking')
        .select(
          'bookingid,mabooking,trangthai,thanhtien,ngaytao,soluong,khoiluong,'
          'dichvu(tendichvu),loaidogiat(tenloaidogiat),donvitinh(kyhieu)',
        )
        .order('ngaytao', ascending: false);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              LaundryOrderRecord.fromBookingJson(row as Map<String, dynamic>),
        )
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

  Future<void> confirmBooking(int bookingId) async {
    await _client.rpc(
      'confirm_laundry_booking',
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
        .from('donhang')
        .select(
          'donhangid,madonhang,trangthai,thanhtien,ngaytao,'
          'chitietdonhang('
          'soluong,khoiluong,dichvu(tendichvu),'
          'loaidogiat(tenloaidogiat),donvitinh(kyhieu)'
          ')',
        )
        .eq('donhangid', orderId)
        .maybeSingle();

    if (order == null) throw StateError('Không tìm thấy đơn hàng.');

    final events = await _client
        .from('donhang_trangthai')
        .select('trangthaicu,trangthaimoi,lydo,thoigian')
        .eq('donhangid', orderId)
        .order('thoigian');

    return LaundryOrderDetails(
      order: LaundryOrderRecord.fromJson(order),
      events: (events as List<dynamic>)
          .map(
            (event) =>
                LaundryOrderStatusEvent.fromJson(event as Map<String, dynamic>),
          )
          .toList(growable: false),
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
