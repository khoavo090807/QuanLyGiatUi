import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/data/delivery_fee_quote.dart';

enum LaundryBookingStatus {
  awaitingReception('ChoTiepNhan', 'Chờ tiếp nhận'),
  confirmed('DaXacNhan', 'Đã xác nhận'),
  cancelled('DaHuy', 'Đã hủy'),
  completed('HoanThanh', 'Hoàn thành'),
  delivered('DaGiao', 'Đã giao'),
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
      'Đã giao' => delivered,
      _ => unknown,
    },
  );
}

class LaundryPriceOption {
  const LaundryPriceOption({
    required this.priceId,
    required this.serviceId,
    required this.serviceName,
    this.serviceDescription,
    this.processingTimeMinutes,
    required this.itemTypeId,
    required this.itemTypeName,
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
    required this.unitPriceVnd,
    this.serviceTypeId,
    this.serviceTypeName,
  });

  final int priceId;
  final int serviceId;
  final String serviceName;
  final String? serviceDescription;
  final int? processingTimeMinutes;
  final int itemTypeId;
  final String itemTypeName;
  final int unitId;
  final String unitName;
  final String unitSymbol;
  final num unitPriceVnd;
  final int? serviceTypeId;
  final String? serviceTypeName;

  LaundryPriceOption withServiceTypeName(String? value) => LaundryPriceOption(
    priceId: priceId,
    serviceId: serviceId,
    serviceName: serviceName,
    serviceDescription: serviceDescription,
    processingTimeMinutes: processingTimeMinutes,
    itemTypeId: itemTypeId,
    itemTypeName: itemTypeName,
    unitId: unitId,
    unitName: unitName,
    unitSymbol: unitSymbol,
    unitPriceVnd: unitPriceVnd,
    serviceTypeId: serviceTypeId,
    serviceTypeName: value,
  );

  factory LaundryPriceOption.fromJson(Map<String, dynamic> json) {
    return LaundryPriceOption(
      priceId: (json['banggiaid'] as num).toInt(),
      serviceId: (json['dichvuid'] as num).toInt(),
      serviceName: json['tendichvu'] as String,
      serviceDescription: json['mota'] as String?,
      processingTimeMinutes: (json['thoigiandukien'] as num?)?.toInt(),
      itemTypeId: (json['loaidogiatid'] as num).toInt(),
      itemTypeName: json['tenloaidogiat'] as String,
      unitId: (json['donvitinhid'] as num).toInt(),
      unitName: json['tendonvitinh'] as String,
      unitSymbol: json['kyhieu'] as String? ?? '',
      unitPriceVnd: json['dongia'] as num,
      serviceTypeId: (json['loaidichvuid'] as num?)?.toInt(),
      serviceTypeName: json['tenloaidichvu'] as String?,
    );
  }
}

class LaundryItemTypeOption {
  const LaundryItemTypeOption({
    required this.id,
    required this.name,
    this.description,
  });

  final int id;
  final String name;
  final String? description;

  factory LaundryItemTypeOption.fromJson(Map<String, dynamic> json) =>
      LaundryItemTypeOption(
        id: (json['loaidogiatid'] as num).toInt(),
        name: json['tenloaidogiat'] as String,
        description: json['mota'] as String?,
      );
}

class LaundryCatalogData {
  const LaundryCatalogData({required this.itemTypes, required this.prices});

  final List<LaundryItemTypeOption> itemTypes;
  final List<LaundryPriceOption> prices;
}

class CreatedLaundryBooking {
  const CreatedLaundryBooking({
    required this.bookingId,
    required this.bookingNumber,
    required this.estimatedTotalVnd,
    this.itemCount = 1,
    this.pointsUsed = 0,
    this.pointsDiscountVnd = 0,
    this.finalTotalVnd,
    this.pickupDistanceMeters = 0,
    this.pickupDeliveryFeeVnd = 0,
    this.deliveryDistanceMeters = 0,
    this.deliveryFeeVnd = 0,
  });

  final int bookingId;
  final String bookingNumber;
  final num estimatedTotalVnd;
  final int itemCount;
  final int pointsUsed;
  final num pointsDiscountVnd;
  final num? finalTotalVnd;
  final int pickupDistanceMeters;
  final num pickupDeliveryFeeVnd;
  final int deliveryDistanceMeters;
  final num deliveryFeeVnd;
  num get totalDeliveryFeeVnd => pickupDeliveryFeeVnd + deliveryFeeVnd;

  factory CreatedLaundryBooking.fromJson(Map<String, dynamic> json) {
    final estimatedTotal = json['thanhtien'] as num;
    final pointsDiscount = json['tiengiamdodiem'] as num? ?? 0;
    return CreatedLaundryBooking(
      bookingId: (json['bookingid'] as num).toInt(),
      bookingNumber: json['mabooking'] as String,
      estimatedTotalVnd: estimatedTotal,
      itemCount: (json['itemcount'] as num?)?.toInt() ?? 1,
      pointsUsed: (json['diemsudung'] as num?)?.toInt() ?? 0,
      pointsDiscountVnd: pointsDiscount,
      finalTotalVnd:
          json['thanhtoan'] as num? ?? estimatedTotal - pointsDiscount,
      pickupDistanceMeters:
          (json['pickupdistancemeters'] as num?)?.toInt() ?? 0,
      pickupDeliveryFeeVnd: json['pickupdeliveryfee'] as num? ?? 0,
      deliveryDistanceMeters:
          (json['deliverydistancemeters'] as num?)?.toInt() ?? 0,
      deliveryFeeVnd: json['deliveryfee'] as num? ?? 0,
    );
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

num? _asNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

/// Bookings do not have an order yet, so the final amount must be derived
/// from the persisted booking details and its selected promotion.
num _bookingPromotionDiscount(num subtotalVnd, Map<String, dynamic>? promotion) {
  if (promotion == null || subtotalVnd <= 0) return 0;

  final minimum = _asNum(promotion['GiaTriDonToiThieu']) ?? 0;
  if (subtotalVnd < minimum) return 0;

  final value = _asNum(promotion['GiaTriGiam']) ?? 0;
  final isPercentage = promotion['LoaiKhuyenMai']?.toString() == 'Phần trăm';
  var discount = isPercentage ? subtotalVnd * value / 100 : value;
  final maximum = _asNum(promotion['MucGiamToiDa']);
  if (maximum != null) discount = min(discount, maximum);
  return discount.clamp(0, subtotalVnd);
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _parseAppointment(dynamic dateValue, dynamic timeValue) {
  if (dateValue == null || timeValue == null) return null;
  try {
    final date = DateTime.parse(dateValue.toString());
    final timeParts = timeValue.toString().split(':');
    if (timeParts.length < 2) return date;
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
  } catch (_) {
    return null;
  }
}

String? _deliveryMethodOf(Map<String, dynamic>? source) =>
    _asString(source?['HinhThucGiaoDo']) ?? _asString(source?['HinhThucTraDo']);

String? _deliveryAddressOf(Map<String, dynamic>? source) =>
    _asString(source?['DiaChiGiao']) ?? _asString(source?['DiaChiTra']);

List<LaundryOrderItem> _parseOrderItems(List<dynamic>? details) {
  if (details == null || details.isEmpty) return const [];
  return details.map((entry) {
    final detail = entry as Map<String, dynamic>;
    final service = detail['DichVu'] as Map<String, dynamic>?;
    final itemType = detail['LoaiDoGiat'] as Map<String, dynamic>?;
    final unit = detail['DonViTinh'] as Map<String, dynamic>?;
    final measurement = _asNum(detail['KhoiLuong'] ?? detail['SoLuong']) ?? 0;
    return LaundryOrderItem(
      serviceName: _asString(service?['TenDichVu']) ?? 'Dịch vụ',
      itemTypeName: _asString(itemType?['TenLoaiDoGiat']) ?? 'Đồ giặt',
      unitSymbol: _asString(unit?['KyHieu']) ?? '',
      measurement: measurement,
      unitPriceVnd: _asNum(detail['DonGia']) ?? 0,
      totalVnd: _asNum(detail['ThanhTien']) ?? 0,
    );
  }).toList(growable: false);
}

class LaundryOrderRecord {
  const LaundryOrderRecord({
    required this.orderId,
    this.bookingId,
    this.pickupMethod,
    this.deliveryMethod,
    this.pickupAddress,
    this.deliveryAddress,
    this.appointment,
    this.notes,
    this.paymentMethod,
    this.items,
    this.subtotalVnd,
    this.pointsUsed = 0,
    this.pointsDiscountVnd = 0,
    this.promotionDiscountVnd,
    this.promotionCode,
    this.finalTotalVnd,
    this.bookingNumber,
    required this.orderNumber,
    required this.status,
    required this.totalVnd,
    required this.createdAt,
    required this.lineDescription,
    this.canCancelBooking = false,
    this.hasLaundryDetails = true,
    this.pickupDistanceMeters = 0,
    this.pickupDeliveryFeeVnd = 0,
    this.deliveryDistanceMeters = 0,
    this.deliveryLegFeeVnd = 0,
  });

  final int? orderId;
  final int? bookingId;
  final String? pickupMethod;
  final String? deliveryMethod;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime? appointment;
  final String? notes;
  final String? paymentMethod;
  final List<LaundryOrderItem>? items;
  final num? subtotalVnd;
  final int pointsUsed;
  final num pointsDiscountVnd;
  final num? promotionDiscountVnd;
  final String? promotionCode;
  final num? finalTotalVnd;
  final String? bookingNumber;
  final String orderNumber;
  final String status;
  final num totalVnd;
  final DateTime createdAt;
  final String lineDescription;
  final bool canCancelBooking;
  final bool hasLaundryDetails;
  final int pickupDistanceMeters;
  final num pickupDeliveryFeeVnd;
  final int deliveryDistanceMeters;
  final num deliveryLegFeeVnd;

  String? get logisticsSummary {
    final methods = <String>[];
    if (pickupMethod != null) {
      methods.add('Hình thức nhân viên nhận đồ: $pickupMethod');
    }
    if (deliveryMethod != null) {
      methods.add('Hình thức nhân viên giao đồ: $deliveryMethod');
    }
    return methods.isEmpty ? null : methods.join(' · ');
  }

  factory LaundryOrderRecord.fromJson(Map<String, dynamic> json) {
    final details = json['ChiTietDonHang'] as List<dynamic>? ?? const [];
    final booking = json['Booking'] as Map<String, dynamic>?;
    final items = _parseOrderItems(details);
    final descriptions = items.map(
      (item) =>
          '${item.serviceName} · ${item.itemTypeName} · '
          '${item.measurement} ${item.unitSymbol}',
    );
    final promotion =
        json['KhuyenMai'] as Map<String, dynamic>? ??
        booking?['KhuyenMai'] as Map<String, dynamic>?;

    return LaundryOrderRecord(
      orderId: _asInt(json['DonHangID']),
      bookingId: _asInt(json['BookingID'] ?? booking?['BookingID']),
      bookingNumber: _asString(booking?['MaBooking']),
      pickupMethod: _asString(booking?['HinhThucNhanDo']),
      deliveryMethod: _deliveryMethodOf(booking),
      pickupAddress: _asString(booking?['DiaChiNhan']),
      deliveryAddress: _deliveryAddressOf(booking),
      appointment: _parseAppointment(booking?['NgayHen'], booking?['GioHen']),
      notes: _asString(booking?['GhiChu']),
      paymentMethod: _asString(booking?['PhuongThucThanhToan']),
      items: items.isEmpty ? null : items,
      subtotalVnd: _asNum(json['TongTien']),
      pointsUsed: _asInt(json['DiemSuDung'] ?? booking?['DiemSuDung']) ?? 0,
      pointsDiscountVnd:
          _asNum(json['TienGiamDoDiem'] ?? booking?['TienGiamDoDiem']) ?? 0,
      promotionDiscountVnd: _asNum(json['TienGiamKhuyenMai']),
      promotionCode: _asString(promotion?['MaKhuyenMai']),
      finalTotalVnd: _asNum(json['ThanhTien']),
      orderNumber: json['MaDonHang'] as String,
      status: json['TrangThai'] as String,
      totalVnd: _asNum(json['ThanhTien']) ?? 0,
      createdAt: DateTime.parse(json['NgayTao'] as String),
      lineDescription: descriptions.isEmpty
          ? 'Cửa hàng đang kiểm nhận đồ'
          : descriptions.join(', '),
      hasLaundryDetails: items.isNotEmpty,
      pickupDistanceMeters:
          _asInt(booking?['PickupDistanceMeters']) ?? 0,
      pickupDeliveryFeeVnd: _asNum(booking?['PickupDeliveryFee']) ?? 0,
      deliveryDistanceMeters:
          _asInt(booking?['DeliveryDistanceMeters']) ?? 0,
      deliveryLegFeeVnd: _asNum(booking?['DeliveryFee']) ?? 0,
    );
  }

  factory LaundryOrderRecord.fromBookingJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? linkedOrder,
  }) {
    final details = json['ChiTietBooking'] as List<dynamic>? ?? const [];
    final items = _parseOrderItems(details);
    final descriptions = items
        .map(
          (item) =>
              '${item.serviceName} · ${item.itemTypeName} · '
              '${item.measurement} ${item.unitSymbol}',
        )
        .toList();

    final bookingStatus = LaundryBookingStatus.fromDatabase(
      json['TrangThai'] as String,
    );
    final subtotalVnd =
        _asNum(linkedOrder?['TongTien']) ??
        items.fold<num>(0, (sum, item) => sum + item.totalVnd);
    final promotion =
        linkedOrder?['KhuyenMai'] as Map<String, dynamic>? ??
        json['KhuyenMai'] as Map<String, dynamic>?;

    final pointsDiscountVnd =
        _asNum(linkedOrder?['TienGiamDoDiem'] ?? json['TienGiamDoDiem']) ?? 0;
    final pickupFee = _asNum(json['PickupDeliveryFee']) ?? 0;
    final deliveryFee = _asNum(json['DeliveryFee']) ?? 0;
    final promotionDiscountVnd = _asNum(linkedOrder?['TienGiamKhuyenMai']) ??
        _bookingPromotionDiscount(subtotalVnd, promotion);
    final finalTotalVnd = _asNum(linkedOrder?['ThanhTien']) ??
        (subtotalVnd - pointsDiscountVnd - promotionDiscountVnd)
                .clamp(0, double.infinity) +
            pickupFee +
            deliveryFee;

    return LaundryOrderRecord(
      orderId: _asInt(linkedOrder?['DonHangID']),
      bookingId: _asInt(json['BookingID']),
      bookingNumber: _asString(json['MaBooking']),
      pickupMethod: _asString(json['HinhThucNhanDo']),
      deliveryMethod: _deliveryMethodOf(json),
      pickupAddress: _asString(json['DiaChiNhan']),
      deliveryAddress: _deliveryAddressOf(json),
      appointment: _parseAppointment(json['NgayHen'], json['GioHen']),
      notes: _asString(json['GhiChu']),
      paymentMethod: _asString(json['PhuongThucThanhToan']),
      items: items.isEmpty ? null : items,
      subtotalVnd:
          _asNum(linkedOrder?['TongTien']) ??
          (items.isEmpty ? null : subtotalVnd),
      pointsUsed:
          _asInt(linkedOrder?['DiemSuDung'] ?? json['DiemSuDung']) ?? 0,
      pointsDiscountVnd: pointsDiscountVnd,
      promotionDiscountVnd: promotionDiscountVnd,
      promotionCode: _asString(promotion?['MaKhuyenMai']),
      finalTotalVnd: finalTotalVnd,
      orderNumber: json['MaBooking'] as String,
      status:
          linkedOrder?['TrangThai'] as String? ?? bookingStatus.displayValue,
      totalVnd: finalTotalVnd,
      createdAt: DateTime.parse(json['NgayTao'] as String),
      lineDescription: descriptions.isEmpty
          ? 'Cửa hàng sẽ kiểm nhận đồ và báo giá'
          : descriptions.join(', '),
      canCancelBooking: bookingStatus == LaundryBookingStatus.awaitingReception,
      hasLaundryDetails: items.isNotEmpty,
      pickupDistanceMeters: _asInt(json['PickupDistanceMeters']) ?? 0,
      pickupDeliveryFeeVnd: _asNum(json['PickupDeliveryFee']) ?? 0,
      deliveryDistanceMeters: _asInt(json['DeliveryDistanceMeters']) ?? 0,
      deliveryLegFeeVnd: _asNum(json['DeliveryFee']) ?? 0,
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
    this.deliveryMethod,
    this.paymentMethod,
    this.address,
    this.deliveryAddress,
    this.appointment,
    this.notes,
    this.items,
    this.subtotalVnd,
    this.deliveryFeeVnd = 0,
    this.pointsUsed = 0,
    this.pointsDiscountVnd = 0,
    this.promotionDiscountVnd,
    this.promotionApplied = false,
    this.promotionCode,
    this.finalTotalVnd,
  });

  final LaundryOrderRecord order;
  final List<LaundryOrderStatusEvent> events;
  final String? pickupMethod;
  final String? deliveryMethod;
  final String? paymentMethod;
  final String? address;
  final String? deliveryAddress;
  final DateTime? appointment;
  final String? notes;
  final List<LaundryOrderItem>? items;
  final num? subtotalVnd;
  final num deliveryFeeVnd;
  final int pointsUsed;
  final num pointsDiscountVnd;
  final num? promotionDiscountVnd;
  final bool promotionApplied;
  final String? promotionCode;
  final num? finalTotalVnd;
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
          'dichvu!inner(tendichvu,loaidichvuid,trangthai,mota,thoigiandukien),'
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
            'mota': service['mota'],
            'thoigiandukien': service['thoigiandukien'],
            'loaidichvuid': service['loaidichvuid'],
            'tenloaidogiat': itemType['tenloaidogiat'],
            'tendonvitinh': unit['tendonvitinh'],
            'kyhieu': unit['kyhieu'],
          });
        })
        .toList(growable: false);
  }

  Future<LaundryCatalogData> getActiveLaundryCatalog() async {
    final pricesFuture = getActivePrices();
    final itemTypesFuture = _client
        .from('loaidogiat')
        .select('loaidogiatid,tenloaidogiat,mota')
        .eq('trangthai', 'Hoạt động')
        .order('tenloaidogiat');
    final serviceTypesFuture = _client
        .from('loaidichvu')
        .select('loaidichvuid,tenloaidichvu')
        .eq('trangthai', 'Hoạt động');

    final prices = await pricesFuture;
    final itemTypeRows = await itemTypesFuture as List<dynamic>;
    final serviceTypeRows = await serviceTypesFuture as List<dynamic>;
    final serviceTypeNames = <int, String>{
      for (final row in serviceTypeRows.cast<Map<String, dynamic>>())
        (row['loaidichvuid'] as num).toInt():
            row['tenloaidichvu'] as String,
    };

    return LaundryCatalogData(
      itemTypes: itemTypeRows
          .cast<Map<String, dynamic>>()
          .map(LaundryItemTypeOption.fromJson)
          .toList(growable: false),
      prices: prices
          .map(
            (price) => price.withServiceTypeName(
              price.serviceTypeId == null
                  ? null
                  : serviceTypeNames[price.serviceTypeId],
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<LaundryOrderRecord>> getCustomerOrders({bool includeDetails = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    try {
      final detailsSelect = includeDetails
          ? ',ChiTietDonHang('
              'SoLuong,KhoiLuong,DonGia,ThanhTien,'
              'DichVu(TenDichVu),LoaiDoGiat(TenLoaiDoGiat),DonViTinh(KyHieu)'
              ')'
          : '';
      final bookingSelect = includeDetails
          ? 'Booking('
              'BookingID,MaBooking,HinhThucNhanDo,HinhThucGiaoDo,DiaChiNhan,DiaChiGiao,'
              'PickupDistanceMeters,PickupDeliveryFee,DeliveryDistanceMeters,DeliveryFee,'
              'NgayHen,GioHen,GhiChu,PhuongThucThanhToan,'
              'DiemSuDung,TienGiamDoDiem,KhuyenMai(MaKhuyenMai,LoaiKhuyenMai,GiaTriGiam,GiaTriDonToiThieu,MucGiamToiDa)'
              ')'
          : 'Booking(BookingID,MaBooking)';
      final rows = await _client
          .from('DonHang')
          .select(
            'DonHangID,BookingID,MaDonHang,TrangThai,TongTien,DiemSuDung,'
            'TienGiamDoDiem,TienGiamKhuyenMai,ThanhTien,NgayTao,'
            'KhuyenMai(MaKhuyenMai),'
            '$bookingSelect'
            '$detailsSelect',
          )
          .order('NgayTao', ascending: false);

      return (rows as List<dynamic>)
          .map(
            (row) => LaundryOrderRecord.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('Lỗi tải đơn hàng khách: $e');
      rethrow;
    }
  }

  Future<List<LaundryOrderRecord>> getStaffOrders() =>
      getCustomerOrders(includeDetails: true);

  Future<List<LaundryOrderRecord>> getCustomerHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập để xem lịch sử.');
    }

    final ordersFuture = getCustomerOrders(includeDetails: true);
    final bookingsFuture = _getBookings(includeDetails: true);
    List<LaundryOrderRecord> orders = const [];
    List<LaundryOrderRecord> bookings = const [];
    Object? ordersError;
    Object? bookingsError;

    try {
      orders = await ordersFuture;
    } catch (error) {
      ordersError = error;
      debugPrint('Không tải được danh sách đơn hàng: $error');
    }
    try {
      bookings = await bookingsFuture;
    } catch (error) {
      bookingsError = error;
      debugPrint('Không tải được danh sách yêu cầu đặt giặt: $error');
    }

    if (ordersError != null && bookingsError != null) {
      throw StateError('Không thể tải lịch sử đơn hàng.');
    }

    final orderBookingIds = orders
        .map((order) => order.bookingId)
        .whereType<int>()
        .toSet();
    final unlinkedBookings = bookings.where(
      (booking) => !orderBookingIds.contains(booking.bookingId),
    );
    return [...orders, ...unlinkedBookings]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<LaundryOrderRecord>> getStaffQueue() async {
    final results = await Future.wait([
      getStaffOrders(),
      _getBookings(includeDetails: true),
    ]);
    final pendingBookings = results[1].where(
      (booking) => booking.canCancelBooking,
    );
    return [...results[0], ...pendingBookings]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<LaundryOrderRecord>> _getBookings({bool includeDetails = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    try {
      final bookingSelect = includeDetails
          ? 'BookingID,MaBooking,TrangThai,NgayTao,'
              'HinhThucNhanDo,HinhThucGiaoDo,DiaChiNhan,DiaChiGiao,'
              'PickupDistanceMeters,PickupDeliveryFee,DeliveryDistanceMeters,DeliveryFee,'
              'NgayHen,GioHen,GhiChu,PhuongThucThanhToan,'
              'DiemSuDung,TienGiamDoDiem,KhuyenMai(MaKhuyenMai,LoaiKhuyenMai,GiaTriGiam,GiaTriDonToiThieu,MucGiamToiDa)'
          : 'BookingID,MaBooking,TrangThai,NgayTao';
      final bookings = await _client
          .from('Booking')
          .select(bookingSelect)
          .order('NgayTao', ascending: false);

      final bookingIds = (bookings as List<dynamic>)
          .map((b) => _asInt((b as Map<String, dynamic>)['BookingID']))
          .whereType<int>()
          .toList();

      final chiTietMap = <int, List<dynamic>>{};
      if (includeDetails && bookingIds.isNotEmpty) {
        final chiTietRows = await _client
            .from('ChiTietBooking')
            .select(
              'BookingID,SoLuong,KhoiLuong,DonGia,ThanhTien,'
              'DichVu(TenDichVu),LoaiDoGiat(TenLoaiDoGiat),DonViTinh(KyHieu)',
            )
            .inFilter('BookingID', bookingIds);

        for (final row in chiTietRows as List<dynamic>) {
          final detail = row as Map<String, dynamic>;
          final bookingId = _asInt(detail['BookingID']);
          if (bookingId == null) continue;
          chiTietMap.putIfAbsent(bookingId, () => []).add(detail);
        }

      }

      return (bookings as List<dynamic>)
          .map((row) {
            final booking = row as Map<String, dynamic>;
            final bookingId = _asInt(booking['BookingID']);
            final details = bookingId == null
                ? const <dynamic>[]
                : chiTietMap[bookingId] ?? const [];
            return LaundryOrderRecord.fromBookingJson({
              ...booking,
              'ChiTietBooking': details,
            });
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('Lỗi tải yêu cầu đặt giặt: $e');
      rethrow;
    }
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
          'DonHangID,BookingID,MaDonHang,TrangThai,TongTien,DiemSuDung,'
          'TienGiamDoDiem,KhuyenMaiID,TienGiamKhuyenMai,PhiGiaoHang,'
          'ThanhTien,NgayTao,KhuyenMai(MaKhuyenMai),'
          'ChiTietDonHang('
          'SoLuong,KhoiLuong,DonGia,ThanhTien,'
          'DichVu(TenDichVu),'
          'LoaiDoGiat(TenLoaiDoGiat),'
          'DonViTinh(KyHieu)'
          ')',
        )
        .eq('DonHangID', orderId)
        .maybeSingle();

    if (order == null) throw StateError('Không tìm thấy đơn hàng.');

    // Lấy dữ liệu Booking riêng biệt nếu BookingID tồn tại
    Map<String, dynamic>? booking;
    final bookingId = _asInt(order['BookingID']);
    if (bookingId != null) {
      try {
        booking = await _client
            .from('Booking')
            .select(
              'HinhThucNhanDo,HinhThucGiaoDo,DiaChiNhan,DiaChiGiao,'
              'PickupDistanceMeters,PickupDeliveryFee,DeliveryDistanceMeters,DeliveryFee,'
              'NgayHen,GioHen,GhiChu,PhuongThucThanhToan,'
              'DiemSuDung,TienGiamDoDiem,KhuyenMai(MaKhuyenMai)',
            )
            .eq('BookingID', bookingId)
            .maybeSingle();
      } catch (e) {
        debugPrint('Lỗi lấy dữ liệu Booking $bookingId: $e');
        // Tiếp tục nếu không lấy được Booking
      }
    }

    List<dynamic> eventsList = [];
    try {
      final eventsResponse = await _client.rpc(
        'get_laundry_order_status_history',
        params: {'p_donhangid': orderId},
      );
      if (eventsResponse is List<dynamic>) {
        eventsList = eventsResponse;
      }
    } catch (e) {
      // RPC gọi thất bại, vẫn tiếp tục với danh sách trống
      debugPrint('Lỗi lấy lịch sử trạng thái đơn hàng $orderId: $e');
    }

    DateTime? appointment;
    if (booking != null &&
        booking['NgayHen'] != null &&
        booking['GioHen'] != null) {
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
    final items = details
        .map((entry) {
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
        })
        .toList(growable: false);

    return LaundryOrderDetails(
      order: LaundryOrderRecord.fromJson({
        ...order,
        if (booking != null) 'Booking': booking,
      }),
      events: eventsList
          .map(
            (event) =>
                LaundryOrderStatusEvent.fromJson(event as Map<String, dynamic>),
          )
          .toList(growable: false),
      pickupMethod: _asString(booking?['HinhThucNhanDo']),
      deliveryMethod: _deliveryMethodOf(booking),
      paymentMethod:
          _asString(booking?['PhuongThucThanhToan']) ??
          await _getPaymentMethod(orderId),
      address: _asString(booking?['DiaChiNhan']),
      deliveryAddress: _deliveryAddressOf(booking),
      appointment: appointment,
      notes: _asString(booking?['GhiChu']),
      items: items.isNotEmpty ? items : null,
      subtotalVnd: order['TongTien'] as num?,
      deliveryFeeVnd: order['PhiGiaoHang'] as num? ?? 0,
      pointsUsed: (order['DiemSuDung'] as num?)?.toInt() ?? 0,
      pointsDiscountVnd: order['TienGiamDoDiem'] as num? ?? 0,
      promotionDiscountVnd: order['TienGiamKhuyenMai'] as num? ?? 0,
      promotionApplied: order['KhuyenMaiID'] != null,
      promotionCode:
          (order['KhuyenMai'] as Map<String, dynamic>?)?['MaKhuyenMai']
              as String?,
      finalTotalVnd: order['ThanhTien'] as num?,
    );
  }

  Future<LaundryOrderDetails> getBookingDetails(int bookingId) async {
    final booking = await _client
        .from('Booking')
        .select(
          'BookingID,MaBooking,TrangThai,NgayTao,HinhThucNhanDo,HinhThucGiaoDo,'
          'DiaChiNhan,DiaChiGiao,PickupDistanceMeters,PickupDeliveryFee,'
          'DeliveryDistanceMeters,DeliveryFee,NgayHen,GioHen,GhiChu,PhuongThucThanhToan,'
          'DiemSuDung,TienGiamDoDiem,KhuyenMaiID,'
          'KhuyenMai(MaKhuyenMai,LoaiKhuyenMai,GiaTriGiam,GiaTriDonToiThieu,MucGiamToiDa),'
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

    final linkedOrder = await _client
        .from('DonHang')
        .select(
          'DonHangID,TrangThai,TongTien,DiemSuDung,TienGiamDoDiem,KhuyenMaiID,'
          'TienGiamKhuyenMai,PhiGiaoHang,ThanhTien,KhuyenMai(MaKhuyenMai)',
        )
        .eq('BookingID', bookingId)
        .maybeSingle();
    final record = LaundryOrderRecord.fromBookingJson(
      booking,
      linkedOrder: linkedOrder,
    );
    // Booking remains the current quote until an order is created.  Therefore
    // recalculate from its saved lines on every refresh, so an adjustment
    // saved by staff on the web is immediately reflected to the customer.
    final bookingSubtotalVnd = (linkedOrder?['TongTien'] as num?) ??
        (booking['ChiTietBooking'] as List<dynamic>? ?? const <dynamic>[])
            .fold<num>(
              0,
              (total, item) =>
                  total + ((item as Map<String, dynamic>)['ThanhTien'] as num? ?? 0),
            );
    final promotion =
        (linkedOrder?['KhuyenMai'] as Map<String, dynamic>?) ??
        (booking['KhuyenMai'] as Map<String, dynamic>?);
    final bookingPointsDiscountVnd =
        (linkedOrder?['TienGiamDoDiem'] as num?) ??
        (booking['TienGiamDoDiem'] as num?) ??
        0;
    final bookingPromotionDiscountVnd =
        (linkedOrder?['TienGiamKhuyenMai'] as num?) ??
        _bookingPromotionDiscount(bookingSubtotalVnd, promotion);
    final bookingDeliveryFeeVnd =
        (_asNum(booking['PickupDeliveryFee']) ?? 0) +
        (_asNum(booking['DeliveryFee']) ?? 0);
    final bookingFinalTotalVnd = (linkedOrder?['ThanhTien'] as num?) ??
        (bookingSubtotalVnd -
                bookingPointsDiscountVnd -
                bookingPromotionDiscountVnd)
            .clamp(0, double.infinity) +
        bookingDeliveryFeeVnd;
    final linkedOrderId = (linkedOrder?['DonHangID'] as num?)?.toInt();
    var events = <dynamic>[];
    if (linkedOrderId != null) {
      try {
        final eventsResponse = await _client.rpc(
          'get_laundry_order_status_history',
          params: {'p_donhangid': linkedOrderId},
        );
        events = eventsResponse is List<dynamic> ? eventsResponse : <dynamic>[];
      } catch (e) {
        debugPrint('Lỗi lấy lịch sử trạng thái đơn hàng $linkedOrderId: $e');
      }
    }

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
    final items = details
        .map((entry) {
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
        })
        .toList(growable: false);

    return LaundryOrderDetails(
      order: record,
      events: events
          .map(
            (event) =>
                LaundryOrderStatusEvent.fromJson(event as Map<String, dynamic>),
          )
          .toList(growable: false),
      pickupMethod: booking['HinhThucNhanDo'] as String?,
      deliveryMethod: _deliveryMethodOf(booking),
      paymentMethod:
          _asString(booking['PhuongThucThanhToan']) ??
          (linkedOrderId == null ? null : await _getPaymentMethod(linkedOrderId)),
      address: booking['DiaChiNhan'] as String?,
      deliveryAddress: _deliveryAddressOf(booking),
      appointment: appointment,
      notes: booking['GhiChu'] as String?,
      items: items.isNotEmpty ? items : null,
      subtotalVnd: bookingSubtotalVnd,
      deliveryFeeVnd: linkedOrder?['PhiGiaoHang'] as num? ?? bookingDeliveryFeeVnd,
      pointsUsed:
          (linkedOrder?['DiemSuDung'] as num?)?.toInt() ??
          (booking['DiemSuDung'] as num?)?.toInt() ??
          0,
      pointsDiscountVnd: bookingPointsDiscountVnd,
      promotionDiscountVnd: bookingPromotionDiscountVnd,
      promotionApplied:
          linkedOrder?['KhuyenMaiID'] != null || booking['KhuyenMaiID'] != null,
      promotionCode:
          ((linkedOrder?['KhuyenMai'] as Map<String, dynamic>?) ??
                  (booking['KhuyenMai']
                      as Map<String, dynamic>?))?['MaKhuyenMai']
              as String?,
      finalTotalVnd: bookingFinalTotalVnd,
    );
  }

  Future<String?> _getPaymentMethod(int orderId) async {
    final rows = await _client
        .from('ThanhToan')
        .select('PhuongThuc')
        .eq('DonHangID', orderId)
        .order('ThoiGian', ascending: false)
        .limit(1);
    final payments = rows as List<dynamic>;
    if (payments.isEmpty) return null;
    return (payments.first as Map<String, dynamic>)['PhuongThuc'] as String?;
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

    final fullName = user.userMetadata?['full_name'] as String? ?? 'Khách hàng';

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': fullName},
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

    final booking = CreatedLaundryBooking.fromJson(
      result as Map<String, dynamic>,
    );

    return booking;
  }

  Future<CreatedLaundryBooking> submitCartOrder({
    required Iterable<CartItem> items,
    required bool usePoints,
    required String paymentMethod,
    required String pickupMethod,
    required String deliveryMethod,
    required String? address,
    String? deliveryAddress,
    required DateTime appointment,
    required String notes,
    required String idempotencyKey,
    String? promotionCode,
    String? deliveryFeeQuoteId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập trước khi đặt đơn.');
    }

    final fullName = user.userMetadata?['full_name'] as String? ?? 'Khách hàng';

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': fullName},
    );

    final itemsJson = items.map((item) => item.toJson()).toList();
    final trimmedNotes = notes.trim().isEmpty ? null : notes.trim();

    final result = await _client.rpc(
      'submit_laundry_booking_with_delivery',
      params: {
        'p_items': itemsJson,
        'p_use_points': usePoints,
        'p_phuongthucthanhtoan': paymentMethod,
        'p_hinhthucnhando': pickupMethod,
        'p_hinhthucgiaodo': deliveryMethod,
        'p_diachinhan': address,
        'p_diachigiao': deliveryAddress,
        'p_delivery_fee_quote_id': deliveryFeeQuoteId,
        'p_ngayhen': _formatDate(appointment),
        'p_giohen': _formatTime(appointment),
        'p_ghichu': trimmedNotes,
        'p_idempotency_key': idempotencyKey,
        'p_makhuyenmai': promotionCode?.trim().isNotEmpty == true
            ? promotionCode!.trim()
            : null,
      },
    );

    final booking = CreatedLaundryBooking.fromJson(
      result as Map<String, dynamic>,
    );

    return booking;
  }

  Future<CreatedLaundryBooking> submitBookingWithoutDetails({
    required String paymentMethod,
    required String pickupMethod,
    required String deliveryMethod,
    required String? address,
    String? deliveryAddress,
    required DateTime appointment,
    required String notes,
    required String idempotencyKey,
    String? promotionCode,
    String? deliveryFeeQuoteId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Bạn cần đăng nhập trước khi đặt đơn.');
    }

    final fullName = user.userMetadata?['full_name'] as String? ?? 'Khách hàng';

    await _client.rpc(
      'complete_google_customer_profile',
      params: {'p_full_name': fullName},
    );

    final result = await _client.rpc(
      'submit_laundry_booking_with_delivery',
      params: {
        'p_items': null,
        'p_use_points': false,
        'p_phuongthucthanhtoan': paymentMethod,
        'p_hinhthucnhando': pickupMethod,
        'p_hinhthucgiaodo': deliveryMethod,
        'p_diachinhan': address,
        'p_diachigiao': deliveryAddress,
        'p_delivery_fee_quote_id': deliveryFeeQuoteId,
        'p_ngayhen': _formatDate(appointment),
        'p_giohen': _formatTime(appointment),
        'p_ghichu': notes.trim().isEmpty ? null : notes.trim(),
        'p_idempotency_key': idempotencyKey,
        'p_makhuyenmai': promotionCode?.trim().isNotEmpty == true
            ? promotionCode!.trim()
            : null,
      },
    );

    final booking = CreatedLaundryBooking.fromJson(
      result as Map<String, dynamic>,
    );

    return booking;
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

  Future<DeliveryFeeQuote> getDeliveryFeeQuote({
    String? pickupAddress,
    String? deliveryAddress,
  }) async {
    final response = await _client.functions.invoke(
      'delivery-fee-quote',
      body: {
        'pickupAddress': pickupAddress,
        'deliveryAddress': deliveryAddress,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(message ?? 'Không tính được phí giao nhận.');
    }
    return DeliveryFeeQuote.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
