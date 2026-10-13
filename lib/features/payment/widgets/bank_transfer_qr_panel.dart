import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/payment/data/payment_repository.dart';

class BankTransferQrPanel extends StatefulWidget {
  const BankTransferQrPanel({
    required this.orderId,
    required this.orderStatus,
    super.key,
  });

  final int orderId;
  final String orderStatus;

  @override
  State<BankTransferQrPanel> createState() => _BankTransferQrPanelState();
}

class _BankTransferQrPanelState extends State<BankTransferQrPanel> {
  final _repository = PaymentRepository();
  late Future<PaymentDetails> _detailsFuture;
  late Future<BankTransferConfig> _configFuture;
  RealtimeChannel? _channel;
  Timer? _fallbackRefresh;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
    _configFuture = _repository.getBankTransferConfig();
    final client = Supabase.instance.client;
    _channel = client
        .channel('order-payment:${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ThanhToan',
          callback: (_) => _refreshDetails(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'HoaDon',
          callback: (_) => _refreshDetails(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'DonHang',
          callback: (_) => _refreshDetails(),
        )
        .subscribe();
    _fallbackRefresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshDetails(),
    );
  }

  Future<PaymentDetails> _loadDetails() =>
      _repository.getPaymentDetails(widget.orderId);

  void _refreshDetails() {
    if (!mounted) return;
    setState(() {
      _detailsFuture = _loadDetails();
    });
  }

  void _refreshConfig() {
    setState(() {
      _configFuture = _repository.getBankTransferConfig();
    });
  }

  @override
  void dispose() {
    _fallbackRefresh?.cancel();
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  String _paymentReference(BankTransferConfig config) =>
      '${config.paymentPrefix}${widget.orderId.toString().padLeft(8, '0')}';

  Uri _qrUri(BankTransferConfig config, PaymentInvoice invoice) => Uri.https(
    'img.vietqr.io',
    '/image/${config.bankBin}-${config.accountNumber}-compact2.png',
    {
      'amount': '${invoice.total.round()}',
      'addInfo': _paymentReference(config),
      'accountName': config.accountName,
    },
  );

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép $label.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaymentDetails>(
      future: _detailsFuture,
      builder: (context, detailsSnapshot) {
        if (detailsSnapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (detailsSnapshot.hasError || !detailsSnapshot.hasData) {
          return const _PaymentNotice(
            text: 'Chưa tải được thông tin hóa đơn. Vui lòng kéo xuống để thử lại.',
          );
        }

        final details = detailsSnapshot.data!;
        final invoice = details.invoice;
        if (invoice == null) {
          return const _PaymentNotice(
            text: 'Mã QR sẽ xuất hiện tại đây khi cửa hàng tạo hóa đơn và chốt số tiền.',
          );
        }
        final isPaid = invoice.status == 'Đã thanh toán' ||
            details.payments.any((payment) => payment.status == 'Thành công');
        if (isPaid) {
          return const _PaymentNotice(
            success: true,
            text: 'Đã nhận được thanh toán cho đơn hàng này.',
          );
        }
        if (invoice.status != 'Chưa thanh toán') {
          return const _PaymentNotice(
            text: 'Hóa đơn hiện không thể thanh toán bằng chuyển khoản.',
          );
        }
        if (widget.orderStatus == 'Đã hủy') {
          return const _PaymentNotice(
            text: 'Đơn hàng đã hủy nên không thể thanh toán.',
          );
        }

        return FutureBuilder<BankTransferConfig>(
          future: _configFuture,
          builder: (context, configSnapshot) {
            if (configSnapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final config = configSnapshot.data;
            if (configSnapshot.hasError || config == null) {
              final error = configSnapshot.error;
              return _PaymentNotice(
                text: error is PaymentConfigLoadException
                    ? error.message
                    : 'Không tải được cấu hình QR từ máy chủ.',
                onRetry: _refreshConfig,
              );
            }
            if (!config.enabled || config.bankBin != '970422') {
              return const _PaymentNotice(
                text: 'Máy chủ chưa cấu hình tài khoản nhận MB Bank. Vui lòng kiểm tra cấu hình VietQR trên web.',
              );
            }

            final reference = _paymentReference(config);
            return Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thanh toán chuyển khoản',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text(
                      'Quét mã bằng ứng dụng ngân hàng. Mã QR đã điền sẵn số tiền và nội dung cho đơn hàng này.',
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Image.network(
                        _qrUri(config, invoice).toString(),
                        width: 250,
                        height: 250,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 250,
                          height: 180,
                          child: Center(child: Text('Không tải được mã QR.')),
                        ),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : const SizedBox(
                                    width: 250,
                                    height: 250,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CopyablePaymentValue(
                      label: 'Ngân hàng',
                      value: config.bankName,
                    ),
                    _CopyablePaymentValue(
                      label: 'Số tài khoản',
                      value: config.accountNumber,
                      onTap: () => _copy(config.accountNumber, 'số tài khoản'),
                    ),
                    _CopyablePaymentValue(
                      label: 'Chủ tài khoản',
                      value: config.accountName,
                    ),
                    _CopyablePaymentValue(
                      label: 'Số tiền',
                      value: FormatterUtils.formatVnd(invoice.total),
                      onTap: () => _copy('${invoice.total.round()}', 'số tiền'),
                    ),
                    _CopyablePaymentValue(
                      label: 'Nội dung chuyển khoản',
                      value: reference,
                      onTap: () => _copy(reference, 'nội dung chuyển khoản'),
                    ),
                    const SizedBox(height: 8),
                    const _PaymentNotice(
                      text: 'Đơn hàng sẽ tự cập nhật sau khi cửa hàng nhận được tiền và hệ thống đối soát thành công.',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({required this.text, this.success = false, this.onRetry});

  final String text;
  final bool success;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: success ? Colors.green.withValues(alpha: 0.08) : AppColors.background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.info_outline,
          color: success ? Colors.green : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Thử tải lại'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CopyablePaymentValue extends StatelessWidget {
  const _CopyablePaymentValue({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(width: 10),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.copy, size: 15),
          ],
        ],
      ),
    ),
  );
}
