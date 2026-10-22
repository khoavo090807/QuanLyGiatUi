import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/widgets/order_confirmation_info.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_booking_repository.dart';

class StaffDeliveryConfirmationScreen extends StatefulWidget {
  const StaffDeliveryConfirmationScreen({required this.order, super.key});

  final LaundryOrderRecord order;

  @override
  State<StaffDeliveryConfirmationScreen> createState() =>
      _StaffDeliveryConfirmationScreenState();
}

class _StaffDeliveryConfirmationScreenState
    extends State<StaffDeliveryConfirmationScreen> {
  final _repository = StaffBookingRepository();
  bool _isSubmitting = false;

  Future<void> _confirmDelivered() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đã giao đồ'),
        content: const Text('Khách hàng đã nhận đủ đồ giặt?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kiểm tra lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận đã giao'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final orderId = widget.order.orderId;
      if (orderId == null) throw StateError('Không tìm thấy mã đơn hàng.');
      await _repository.advanceDelivery(orderId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xác nhận giao đồ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết giao đồ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('#${order.orderNumber}', style: AppTypography.title),
          const SizedBox(height: 4),
          Text('Trạng thái: ${order.status}', style: AppTypography.bodySmall),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(order.customerName ?? 'Khách hàng'),
              subtitle: Text(order.customerPhone ?? 'Chưa có số điện thoại'),
            ),
          ),
          const SizedBox(height: 8),
          OrderConfirmationInfo(details: order.toDisplayDetails()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _isSubmitting ? null : _confirmDelivered,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Xác nhận đã giao đồ cho khách'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            textStyle: AppTypography.button,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
