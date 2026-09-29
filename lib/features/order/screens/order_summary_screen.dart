import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/laundry_order_pricing.dart';

class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({required this.draft, super.key});

  final Map<String, dynamic> draft;

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final _repository = OrderRepository();
  final _idempotencyKey = OrderRepository.createIdempotencyKey();
  bool _isSubmitting = false;
  String? _errorMessage;
  CreatedLaundryBooking? _createdBooking;

  LaundryPriceOption get _price => widget.draft['price'] as LaundryPriceOption;
  num get _measurement => widget.draft['measurement'] as num;
  String get _pickupMethod => widget.draft['pickupMethod'] as String;
  String? get _address => widget.draft['address'] as String?;
  DateTime get _appointment => widget.draft['appointment'] as DateTime;
  String get _notes => widget.draft['notes'] as String? ?? '';

  int get _estimatedTotalMinorUnits => LaundryOrderPricing.lineTotalMinorUnits(
    unitPriceVnd: _price.unitPriceVnd,
    quantity: _isWeightBased ? null : _measurement,
    weightKg: _isWeightBased ? _measurement : null,
  );

  bool get _isWeightBased =>
      _price.unitSymbol.toLowerCase() == 'kg' ||
      _price.unitSymbol.toLowerCase() == 'kilogram';

  Future<void> _submitOrder() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final booking = await _repository.submitOrder(
        priceId: _price.priceId,
        measurement: _measurement,
        pickupMethod: _pickupMethod,
        address: _address,
        appointment: _appointment,
        notes: _notes,
        idempotencyKey: _idempotencyKey,
      );
      if (mounted) setState(() => _createdBooking = booking);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _messageFor(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is AuthException) return error.message;
    return 'Không thể tạo đơn. Vui lòng kiểm tra kết nối rồi thử lại.';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatVnd(num value) => '${value.toStringAsFixed(0)} đ';

  @override
  Widget build(BuildContext context) {
    final booking = _createdBooking;
    return Scaffold(
      appBar: AppBar(
        title: Text(booking == null ? 'Xác nhận yêu cầu' : 'Đã gửi yêu cầu'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          if (booking != null) ...[
            const Icon(
              Icons.check_circle_outline,
              size: 52,
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            Text('Yêu cầu đang chờ tiếp nhận', style: AppTypography.heading2),
            const SizedBox(height: 4),
            Text(
              'Mã booking ${booking.bookingNumber}',
              style: AppTypography.bodyText.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
          ],
          _SummarySection(
            title: 'Dịch vụ',
            children: [
              _SummaryRow(
                label: 'Dịch vụ',
                value: '${_price.serviceName} · ${_price.itemTypeName}',
              ),
              _SummaryRow(
                label: 'Số lượng dự kiến',
                value: '${_measurement.toString()} ${_price.unitSymbol}',
              ),
              _SummaryRow(
                label: 'Đơn giá',
                value:
                    '${_formatVnd(_price.unitPriceVnd)} / ${_price.unitSymbol}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SummarySection(
            title: 'Nhận đồ',
            children: [
              _SummaryRow(label: 'Hình thức', value: _pickupMethod),
              if (_address != null)
                _SummaryRow(label: 'Địa chỉ', value: _address!),
              _SummaryRow(
                label: 'Lịch hẹn',
                value: _formatDateTime(_appointment),
              ),
              if (_notes.isNotEmpty)
                _SummaryRow(label: 'Ghi chú', value: _notes),
            ],
          ),
          const SizedBox(height: 20),
          _SummarySection(
            title: 'Tạm tính',
            children: [
              _SummaryRow(
                label: 'Tiền dịch vụ',
                value: _formatVnd(_estimatedTotalMinorUnits / 100),
              ),
              if (booking != null)
                _SummaryRow(
                  label: 'Tạm tính theo bảng giá',
                  value: _formatVnd(booking.estimatedTotalVnd),
                  emphasize: true,
                )
              else
                const Text(
                  'Giá cuối cùng có thể được điều chỉnh sau khi cửa hàng kiểm nhận đồ.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error),
            ),
          ],
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: booking == null
                ? FilledButton(
                    onPressed: _isSubmitting ? null : _submitOrder,
                    child: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gửi yêu cầu đặt đơn'),
                  )
                : FilledButton(
                    onPressed: () => context.goNamed(AppRoutes.myOrders),
                    child: const Text('Đến lịch sử đơn hàng'),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.heading3),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: emphasize ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: emphasize ? AppColors.primary : AppColors.textPrimary,
                fontWeight: emphasize ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
