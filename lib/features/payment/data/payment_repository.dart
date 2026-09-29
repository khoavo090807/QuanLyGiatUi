import 'package:supabase_flutter/supabase_flutter.dart';

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
  const PaymentDetails({required this.invoice, required this.payments});

  final PaymentInvoice? invoice;
  final List<PaymentRecord> payments;
}

class PaymentRepository {
  PaymentRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<PaymentDetails> getPaymentDetails(int orderId) async {
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
}