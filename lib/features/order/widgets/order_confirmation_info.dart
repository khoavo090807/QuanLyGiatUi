import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';

class OrderConfirmationInfo extends StatelessWidget {
  const OrderConfirmationInfo({
    required this.details,
    this.compact = false,
    this.lightText = false,
    super.key,
  });

  final LaundryOrderDetails details;
  final bool compact;
  final bool lightText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _servicesSection(),
        SizedBox(height: compact ? 12 : 20),
        _paymentSection(),
        SizedBox(height: compact ? 12 : 20),
        _logisticsSection(),
        SizedBox(height: compact ? 12 : 20),
        _totalsSection(),
      ],
    );
  }

  Widget _servicesSection() {
    final items = details.items ?? const <LaundryOrderItem>[];
    final hasDetails = details.order.hasLaundryDetails && items.isNotEmpty;
    return _Section(
      title: hasDetails ? 'Dịch vụ (${items.length} mục)' : 'Thông tin đồ giặt',
      lightText: lightText,
      children: hasDetails
          ? items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Row(
                      label:
                          '${item.serviceName} · ${item.itemTypeName}\n'
                          '${item.measurement} ${item.unitSymbol}'
                          '${item.unitPriceVnd > 0 ? ' × ${_formatVnd(item.unitPriceVnd)}' : ''}',
                      value: item.totalVnd > 0 ? _formatVnd(item.totalVnd) : '',
                      lightText: lightText,
                    ),
                  ),
                )
                .toList(growable: false)
          : [
              Text(
                'Cửa hàng sẽ kiểm nhận đồ, xác định dịch vụ và báo giá sau khi nhận đồ.',
                style: TextStyle(color: _secondaryColor),
              ),
            ],
    );
  }

  Widget _paymentSection() {
    final paymentMethod = details.paymentMethod ?? 'Chưa ghi nhận';
    return _Section(
      title: 'Thanh toán',
      lightText: lightText,
      children: [
        _Row(label: 'Hình thức', value: paymentMethod, lightText: lightText),
        Text(
          details.paymentMethod == null
              ? 'Chưa có hình thức thanh toán được ghi nhận.'
              : 'Thanh toán sẽ được thực hiện khi cửa hàng hoàn tất kiểm nhận '
                    'và hóa đơn được tạo.',
          style: TextStyle(color: _secondaryColor),
        ),
      ],
    );
  }

  Widget _logisticsSection() {
    return _Section(
      title: 'Thông tin nhận và giao đồ',
      lightText: lightText,
      children: [
        if (details.pickupMethod != null)
          _Row(
            label: 'Hình thức nhân viên nhận đồ',
            value: details.pickupMethod!,
            lightText: lightText,
          ),
        if (details.deliveryMethod != null)
          _Row(
            label: 'Hình thức nhân viên giao đồ',
            value: details.deliveryMethod!,
            lightText: lightText,
          ),
        if (details.address != null && details.address!.isNotEmpty)
          _Row(
            label: 'Địa chỉ lấy đồ',
            value: details.address!,
            lightText: lightText,
          ),
        if (details.deliveryAddress != null &&
            details.deliveryAddress!.isNotEmpty)
          _Row(
            label: 'Địa chỉ giao đồ',
            value: details.deliveryAddress!,
            lightText: lightText,
          ),
        if (details.appointment != null)
          _Row(
            label: 'Lịch hẹn',
            value: _formatDateTime(details.appointment!),
            lightText: lightText,
          ),
        if (details.notes != null && details.notes!.isNotEmpty)
          _Row(label: 'Ghi chú', value: details.notes!, lightText: lightText),
      ],
    );
  }

  Widget _totalsSection() {
    final order = details.order;
    final totalDiscount =
        details.pointsDiscountVnd + (details.promotionDiscountVnd ?? 0);
    return _Section(
      title: order.hasLaundryDetails ? 'Tạm tính' : 'Báo giá',
      lightText: lightText,
      children: [
        if (order.hasLaundryDetails && details.subtotalVnd != null)
          _Row(
            label: 'Tổng tiền đơn hàng theo bảng giá',
            value: _formatVnd(details.subtotalVnd!),
            lightText: lightText,
          )
        else if (!order.hasLaundryDetails)
          Text(
            'Cửa hàng sẽ báo giá sau khi kiểm nhận đồ.',
            style: TextStyle(color: _secondaryColor),
          ),
        if (details.deliveryFeeVnd > 0)
          _Row(
            label: 'Phí giao nhận',
            value: _formatVnd(details.deliveryFeeVnd),
            lightText: lightText,
          ),
        if (details.promotionCode != null && details.promotionCode!.isNotEmpty)
          _Row(
            label: 'Mã khuyến mãi',
            value: details.promotionCode!,
            lightText: lightText,
          ),
        if (details.promotionDiscountVnd case final discount? when discount > 0)
          _Row(
            label: 'Giảm từ mã khuyến mãi',
            value: _formatVnd(discount),
            lightText: lightText,
          ),
        if (details.pointsUsed > 0)
          _Row(
            label: 'Điểm đã sử dụng',
            value: '${details.pointsUsed} điểm',
            lightText: lightText,
          ),
        if (details.pointsDiscountVnd > 0)
          _Row(
            label: 'Giảm từ điểm',
            value: _formatVnd(details.pointsDiscountVnd),
            lightText: lightText,
          ),
        if (order.hasLaundryDetails)
          _Row(
            label: 'Tổng tiền được giảm',
            value: _formatVnd(totalDiscount),
            lightText: lightText,
          ),
        _Row(
          label: 'Tổng tiền cuối cùng khách trả',
          value: details.finalTotalVnd != null
              ? _formatVnd(details.finalTotalVnd!)
              : order.hasLaundryDetails
              ? 'Chờ cửa hàng xác nhận'
              : 'Cửa hàng sẽ báo giá',
          emphasize: true,
          lightText: lightText,
        ),
      ],
    );
  }

  Color get _secondaryColor =>
      lightText ? Colors.white.withValues(alpha: 0.82) : AppColors.textSecondary;

  String _formatVnd(num value) => FormatterUtils.formatVnd(value);

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    required this.lightText,
  });

  final String title;
  final List<Widget> children;
  final bool lightText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.heading3.copyWith(
            color: lightText ? Colors.white : null,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.lightText,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool lightText;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final labelColor = lightText
        ? Colors.white.withValues(alpha: 0.82)
        : AppColors.textSecondary;
    final valueColor = emphasize
        ? (lightText ? Colors.white : AppColors.primary)
        : (lightText ? Colors.white : AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
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
                color: valueColor,
                fontWeight: emphasize ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension LaundryOrderRecordDetails on LaundryOrderRecord {
  LaundryOrderDetails toDisplayDetails() {
    return LaundryOrderDetails(
      order: this,
      events: const [],
      pickupMethod: pickupMethod,
      deliveryMethod: deliveryMethod,
      paymentMethod: paymentMethod,
      address: pickupAddress,
      deliveryAddress: deliveryAddress,
      appointment: appointment,
      notes: notes,
      items: items,
      subtotalVnd: subtotalVnd ?? (items == null || items!.isEmpty ? null : totalVnd),
      pointsUsed: pointsUsed,
      pointsDiscountVnd: pointsDiscountVnd,
      promotionDiscountVnd: promotionDiscountVnd,
      promotionApplied: promotionCode != null && promotionCode!.isNotEmpty,
      promotionCode: promotionCode,
      finalTotalVnd: finalTotalVnd ?? totalVnd,
    );
  }
}
