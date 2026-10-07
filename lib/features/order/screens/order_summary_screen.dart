import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';

import 'package:app_quanly_giaiui/features/main_shell.dart';

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

  List<CartItem> get _cart =>
      List<CartItem>.from(widget.draft['cart'] as List<dynamic>);
  bool get _provideLaundryDetails =>
      widget.draft['provideLaundryDetails'] as bool? ?? true;
  bool get _clearCartAfterSubmit =>
      widget.draft['clearCartAfterSubmit'] as bool? ?? false;
  Set<int>? get _clearCartPriceIds {
    final ids = widget.draft['clearCartPriceIds'];
    return ids is List ? ids.whereType<int>().toSet() : null;
  }
  String get _paymentMethod =>
      widget.draft['paymentMethod'] as String? ?? 'Tiền mặt';
  String get _pickupMethod => widget.draft['pickupMethod'] as String;
  String get _deliveryMethod => widget.draft['deliveryMethod'] as String;
  String? get _address => widget.draft['address'] as String?;
  String? get _deliveryAddress => widget.draft['deliveryAddress'] as String?;
  String? get _deliveryQuoteId => widget.draft['deliveryQuoteId'] as String?;
  DateTime get _appointment => widget.draft['appointment'] as DateTime;
  String get _notes => widget.draft['notes'] as String? ?? '';
  bool get _usePoints => widget.draft['usePoints'] as bool? ?? false;
  int get _pointsUsedEstimate =>
      widget.draft['pointsUsedEstimate'] as int? ?? 0;
  num get _pointsDiscountEstimateVnd =>
      widget.draft['pointsDiscountEstimateVnd'] as num? ?? 0;
  String get _promotionCode => widget.draft['promotionCode'] as String? ?? '';
  num get _promotionDiscountEstimateVnd =>
      widget.draft['promotionDiscountEstimateVnd'] as num? ?? 0;

  int get _estimatedTotalMinorUnits =>
      _cart.fold(0, (total, item) => total + item.estimatedTotalMinorUnits);

  num get _pickupDistanceMeters =>
      _createdBooking?.pickupDistanceMeters ??
      (widget.draft['pickupDistanceMeters'] as num? ?? 0).toInt();
  num get _pickupDeliveryFeeVnd =>
      _createdBooking?.pickupDeliveryFeeVnd ??
      widget.draft['pickupDeliveryFeeVnd'] as num? ?? 0;
  num get _deliveryDistanceMeters =>
      _createdBooking?.deliveryDistanceMeters ??
      (widget.draft['deliveryDistanceMeters'] as num? ?? 0).toInt();
  num get _deliveryFeeVnd =>
      _createdBooking?.deliveryFeeVnd ??
      widget.draft['deliveryFeeVnd'] as num? ?? 0;
  num get _totalDeliveryFeeVnd => _pickupDeliveryFeeVnd + _deliveryFeeVnd;

  num get _estimatedOrderTotalVnd =>
      _createdBooking?.estimatedTotalVnd ?? _estimatedTotalMinorUnits / 100;

  num get _totalDiscountEstimateVnd {
    final pointsDiscount =
        _createdBooking?.pointsDiscountVnd ??
        (_usePoints ? _pointsDiscountEstimateVnd : 0);
    return (_promotionDiscountEstimateVnd + pointsDiscount).clamp(
      0,
      _estimatedOrderTotalVnd,
    );
  }

  num get _estimatedFinalTotalVnd =>
      (_estimatedOrderTotalVnd - _totalDiscountEstimateVnd).clamp(
        0,
        _estimatedOrderTotalVnd,
      ) +
      _totalDeliveryFeeVnd;

  String _distanceLabel(num meters) =>
      '${(meters / 1000).toStringAsFixed(1)} km';

  Future<void> _submitOrder() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final booking = _provideLaundryDetails
          ? await _repository.submitCartOrder(
              items: _cart,
              usePoints: _usePoints,
              paymentMethod: _paymentMethod,
              pickupMethod: _pickupMethod,
              deliveryMethod: _deliveryMethod,
              address: _address,
              deliveryAddress: _deliveryAddress,
              deliveryFeeQuoteId: _deliveryQuoteId,
              appointment: _appointment,
              notes: _notes,
              idempotencyKey: _idempotencyKey,
              promotionCode: _promotionCode,
            )
          : await _repository.submitBookingWithoutDetails(
              paymentMethod: _paymentMethod,
              pickupMethod: _pickupMethod,
              deliveryMethod: _deliveryMethod,
              address: _address,
              deliveryAddress: _deliveryAddress,
              deliveryFeeQuoteId: _deliveryQuoteId,
              appointment: _appointment,
              notes: _notes,
              idempotencyKey: _idempotencyKey,
              promotionCode: _promotionCode,
            );
      if (_clearCartAfterSubmit) {
        final selectedIds = _clearCartPriceIds;
        if (selectedIds == null) {
          CartStore.instance.clear();
        } else {
          CartStore.instance.removePriceIds(selectedIds);
        }
      }
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

  String _formatVnd(num value) => FormatterUtils.formatVnd(value);

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
            title: _provideLaundryDetails
                ? 'Dịch vụ (${_cart.length} mục)'
                : 'Thông tin đồ giặt',
            children: _provideLaundryDetails
                ? _cart
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SummaryRow(
                            label:
                                '${item.price.serviceName} · ${item.price.itemTypeName}\n'
                                '${item.measurement} ${item.price.unitSymbol} × '
                                '${_formatVnd(item.price.unitPriceVnd)}',
                            value: _formatVnd(
                              item.estimatedTotalMinorUnits / 100,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false)
                : const [
                    Text(
                      'Cửa hàng sẽ kiểm nhận đồ, xác định dịch vụ và báo giá sau khi nhận đồ.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
          ),
          const SizedBox(height: 20),
          _SummarySection(
            title: 'Thanh toán',
            children: [
              _SummaryRow(label: 'Hình thức', value: _paymentMethod),
              const Text(
                'Thanh toán sẽ được thực hiện khi cửa hàng hoàn tất kiểm nhận '
                'và hóa đơn được tạo.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SummarySection(
            title: 'Thông tin nhận và giao đồ',
            children: [
              _SummaryRow(
                label: 'Hình thức nhân viên nhận đồ',
                value: _pickupMethod,
              ),
              _SummaryRow(
                label: 'Hình thức nhân viên giao đồ',
                value: _deliveryMethod,
              ),
              if (_address != null)
                _SummaryRow(label: 'Địa chỉ lấy đồ', value: _address!),
              if (_deliveryAddress != null)
                _SummaryRow(
                  label: 'Địa chỉ giao đồ',
                  value: _deliveryAddress!,
                ),
              if (_pickupMethod == 'Tại nhà')
                _SummaryRow(
                  label: 'Phí lấy đồ · ${_distanceLabel(_pickupDistanceMeters)}',
                  value: _formatVnd(_pickupDeliveryFeeVnd),
                ),
              if (_deliveryMethod == 'Tại nhà')
                _SummaryRow(
                  label: 'Phí giao đồ · ${_distanceLabel(_deliveryDistanceMeters)}',
                  value: _formatVnd(_deliveryFeeVnd),
                ),
              if (_totalDeliveryFeeVnd > 0)
                _SummaryRow(
                  label: 'Tổng phí giao nhận',
                  value: _formatVnd(_totalDeliveryFeeVnd),
                ),
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
            title: _provideLaundryDetails ? 'Tạm tính' : 'Báo giá',
            children: [
              if (_provideLaundryDetails)
                _SummaryRow(
                  label: booking == null
                      ? 'Tổng tiền đơn hàng (ước tính)'
                      : 'Tổng tiền đơn hàng theo bảng giá',
                  value: _formatVnd(_estimatedOrderTotalVnd),
                )
              else
                const Text(
                  'Cửa hàng sẽ báo giá sau khi kiểm nhận đồ.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              if (_provideLaundryDetails)
                const Text(
                  'Giá cuối cùng có thể được điều chỉnh sau khi cửa hàng kiểm nhận đồ.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else ...[
                _SummaryRow(
                  label: 'Tổng tiền đơn hàng',
                  value: 'Cửa hàng sẽ báo giá',
                ),
                _SummaryRow(
                  label: 'Tổng tiền được giảm',
                  value: 'Tính sau khi cửa hàng báo giá',
                ),
                _SummaryRow(
                  label: 'Tổng tiền cuối cùng khách trả',
                  value: 'Cửa hàng sẽ báo giá',
                  emphasize: true,
                ),
              ],
              if (_provideLaundryDetails) ...[
                if (_promotionCode.isNotEmpty)
                  _SummaryRow(
                    label: 'Giảm từ mã khuyến mãi',
                    value: _formatVnd(_promotionDiscountEstimateVnd),
                  ),
                if (_usePoints) ...[
                  _SummaryRow(
                    label: booking == null
                        ? 'Điểm dự kiến sử dụng'
                        : 'Điểm đã sử dụng',
                    value: '${booking?.pointsUsed ?? _pointsUsedEstimate} điểm',
                  ),
                  _SummaryRow(
                    label: booking == null
                        ? 'Giảm ước tính từ điểm'
                        : 'Giảm từ điểm',
                    value: _formatVnd(
                      booking?.pointsDiscountVnd ?? _pointsDiscountEstimateVnd,
                    ),
                  ),
                ],
                _SummaryRow(
                  label: 'Tổng tiền được giảm',
                  value: _formatVnd(_totalDiscountEstimateVnd),
                ),
                _SummaryRow(
                  label: 'Tổng tiền cuối cùng khách trả',
                  value: _formatVnd(_estimatedFinalTotalVnd),
                  emphasize: true,
                ),
              ],
              if (_promotionCode.isNotEmpty)
                _SummaryRow(label: 'Mã khuyến mãi', value: _promotionCode),
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
                    onPressed: () => MainShell.goToTab(context, 1),
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
