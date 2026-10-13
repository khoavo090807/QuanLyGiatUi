import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/constants/app_constants.dart';

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.method,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.note,
  });

  final int id;
  final String method;
  final num amount;
  final String status;
  final DateTime createdAt;
  final String? note;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      id: (json['thanhtoanid'] as num).toInt(),
      method: json['phuongthuc'] as String,
      amount: json['sotien'] as num,
      status: json['trangthai'] as String,
      createdAt: DateTime.parse(json['thoigian'] as String),
      note: json['ghichu'] as String?,
    );
  }
}

class PaymentInvoice {
  const PaymentInvoice({
    required this.id,
    required this.number,
    required this.total,
    required this.status,
  });

  final int id;
  final String number;
  final num total;
  final String status;

  factory PaymentInvoice.fromJson(Map<String, dynamic> json) {
    return PaymentInvoice(
      id: (json['hoadonid'] as num).toInt(),
      number: json['mahoadon'] as String,
      total: json['thanhtien'] as num,
      status: json['trangthai'] as String,
    );
  }
}

class PaymentDetails {
  const PaymentDetails({
    required this.invoice,
    required this.payments,
    this.paymentMethod,
  });

  final PaymentInvoice? invoice;
  final List<PaymentRecord> payments;
  final String? paymentMethod;
}

class BankTransferConfig {
  const BankTransferConfig({
    required this.enabled,
    required this.bankBin,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.paymentPrefix,
  });

  final bool enabled;
  final String bankBin;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String paymentPrefix;

  factory BankTransferConfig.fromJson(Map<String, dynamic> json) =>
      BankTransferConfig(
        enabled: json['enabled'] as bool? ?? false,
        bankBin: json['bank_bin'] as String? ?? '',
        bankName: json['bank_name'] as String? ?? '',
        accountNumber: json['account_number'] as String? ?? '',
        accountName: json['account_name'] as String? ?? '',
        paymentPrefix: json['payment_prefix'] as String? ?? 'DH',
      );
}

class PaymentConfigLoadException implements Exception {
  const PaymentConfigLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PaymentRepository {
  PaymentRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<BankTransferConfig> getBankTransferConfig() async {
    try {
      final response = await _dio.get<dynamic>(
        AppConstants.paymentConfigUrl,
        options: Options(responseType: ResponseType.json),
      );
      final responseData = response.data;
      if (responseData is! Map) {
        throw const PaymentConfigLoadException(
          'Máy chủ không trả về JSON cấu hình QR hợp lệ.',
        );
      }

      // The current Laravel endpoint returns the config directly. Accept the
      // standard API envelope too, in case the endpoint is wrapped by a proxy.
      final data = responseData['data'] is Map
          ? Map<String, dynamic>.from(responseData['data'] as Map)
          : Map<String, dynamic>.from(responseData);
      return BankTransferConfig.fromJson(data);
    } on PaymentConfigLoadException {
      rethrow;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        throw PaymentConfigLoadException(
          'Máy chủ cấu hình QR trả về lỗi HTTP $statusCode.',
        );
      }
      throw const PaymentConfigLoadException(
        'Không kết nối được máy chủ cấu hình QR. Kiểm tra Internet rồi thử tải lại.',
      );
    } on FormatException {
      throw const PaymentConfigLoadException(
        'Dữ liệu cấu hình QR từ máy chủ không đúng định dạng.',
      );
    }
  }

  Future<PaymentDetails> getPaymentDetails(int orderId) async {
    final orderJson = await _client
        .from('DonHang')
        .select('BookingID')
        .eq('DonHangID', orderId)
        .maybeSingle();
    final bookingId = (orderJson?['BookingID'] as num?)?.toInt();
    final bookingJson = bookingId == null
        ? null
        : await _client
              .from('Booking')
              .select('PhuongThucThanhToan')
              .eq('BookingID', bookingId)
              .maybeSingle();
    final invoiceJson = await _client
        .from('hoadon')
        .select('hoadonid,mahoadon,thanhtien,trangthai')
        .eq('donhangid', orderId)
        .maybeSingle();
    final paymentJson = await _client
        .from('thanhtoan')
        .select('thanhtoanid,phuongthuc,sotien,trangthai,thoigian,ghichu')
        .eq('donhangid', orderId)
        .order('thoigian', ascending: false);

    return PaymentDetails(
      invoice: invoiceJson == null ? null : PaymentInvoice.fromJson(invoiceJson),
      payments: (paymentJson as List<dynamic>)
          .map((row) => PaymentRecord.fromJson(row as Map<String, dynamic>))
          .toList(growable: false),
      paymentMethod: bookingJson?['PhuongThucThanhToan'] as String?,
    );
  }

  Future<void> requestPayment({
    required int orderId,
    required String method,
    required String idempotencyKey,
  }) async {
    await _client.rpc(
      'request_order_payment',
      params: {
        'p_donhangid': orderId,
        'p_phuongthuc': method,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<void> applyPromotion({
    required int orderId,
    required String code,
  }) => _client.rpc(
    'apply_order_promotion',
    params: {'p_donhangid': orderId, 'p_makhuyenmai': code.trim()},
  );
}
