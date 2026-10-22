import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/widgets/order_confirmation_info.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_booking_repository.dart';
import 'package:app_quanly_giaiui/features/staff/screens/staff_delivery_confirmation_screen.dart';

class StaffOrderQueueScreen extends StatefulWidget {
  const StaffOrderQueueScreen({super.key});

  @override
  State<StaffOrderQueueScreen> createState() => _StaffOrderQueueScreenState();
}

class _StaffOrderQueueScreenState extends State<StaffOrderQueueScreen> {
  final _authRepository = AuthRepository();
  final _orderRepository = OrderRepository();
  final _staffRepository = StaffBookingRepository();
  late Future<_StaffQueueData> _queueFuture;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _queueFuture = _loadQueue();
  }

  Future<_StaffQueueData> _loadQueue() async {
    final roles = await _authRepository.getCurrentRoles().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
          'Không lấy được quyền nhân viên từ phiên đăng nhập. Hãy đăng xuất và đăng nhập lại.',
        );
      },
    );
    if (!roles.any({'Nhân viên', 'Quản lý', 'Chủ cửa hàng'}.contains)) {
      return _StaffQueueData(roles: roles, orders: const []);
    }
    final orders = await _orderRepository.getStaffQueue().timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        throw TimeoutException(
          'Máy chủ mất quá nhiều thời gian để tải đơn. Kiểm tra kết nối API Laravel rồi thử lại.',
        );
      },
    );
    return _StaffQueueData(roles: roles, orders: orders);
  }

  Future<void> _refresh() async {
    final future = _loadQueue();
    setState(() {
      _queueFuture = future;
    });
    await future;
  }

  Future<void> _openInspection(int bookingId) async {
    await context.pushNamed<bool>(
      AppRoutes.staffBookingInspection,
      pathParameters: {'id': bookingId.toString()},
    );
    if (mounted) await _refresh();
  }

  List<String> _nextStatuses(LaundryOrderRecord order) {
    return switch (order.status) {
      'Chờ tiếp nhận' => ['Đã tiếp nhận', 'Đã hủy'],
      'Đã tiếp nhận' => ['Đang giặt', 'Đã hủy'],
      'Đang giặt' => ['Hoàn thành giặt'],
      'Hoàn thành giặt' =>
        order.deliveryMethod == 'Tại nhà'
            ? ['Đang giao']
            : ['Đang giao', 'Đã giao'],
      'Đang giao' => ['Đã giao'],
      _ => const [],
    };
  }

  Future<void> _transition(LaundryOrderRecord order, String newStatus) async {
    if (newStatus == 'Đã giao' && order.deliveryMethod == 'Tại nhà') {
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => StaffDeliveryConfirmationScreen(order: order),
        ),
      );
      if (confirmed == true && mounted) await _refresh();
      return;
    }

    String? reason;
    if (newStatus == 'Đã hủy') {
      reason = await _requestCancellationReason();
      if (reason == null) return;
    }

    setState(() => _isUpdating = true);
    try {
      if (order.orderId != null) {
        if (newStatus == 'Đang giao' && order.deliveryMethod == 'Tại nhà') {
          await _staffRepository.advanceDelivery(order.orderId!);
        } else {
          await _orderRepository.transitionStatus(
            orderId: order.orderId!,
            newStatus: newStatus,
            reason: reason,
          );
        }
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể cập nhật đơn: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<String?> _requestCancellationReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lý do hủy đơn'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Nhập lý do'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Xác nhận hủy'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận đồ & đơn hàng của bạn'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await _authRepository.signOut();
              if (context.mounted) context.goNamed(AppRoutes.login);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<_StaffQueueData>(
        future: _queueFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _QueueState(
              message: _queueErrorMessage(snapshot.error),
              action: TextButton(
                onPressed: _refresh,
                child: const Text('Thử lại'),
              ),
            );
          }

          final queue = snapshot.data!;
          if (!queue.roles.any(
            (role) =>
                role == 'Nhân viên' ||
                role == 'Chủ cửa hàng' ||
                role.startsWith('Quản lý'),
          )) {
            return const _QueueState(
              icon: Icons.lock_outline,
              message: 'Tài khoản không có quyền vận hành đơn hàng.',
            );
          }
          if (queue.orders.isEmpty) {
            return const _QueueState(
              icon: Icons.receipt_long_outlined,
              message: 'Chưa có booking nhận tại nhà nào được phân công.',
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: queue.orders.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _StaffOrderCard(
                order: queue.orders[index],
                nextStatuses: _nextStatuses(queue.orders[index]),
                isUpdating: _isUpdating,
                onInspect: () =>
                    _openInspection(queue.orders[index].bookingId!),
                onTransition: (status) =>
                    _transition(queue.orders[index], status),
              ),
            ),
          );
        },
      ),
    );
  }

  String _queueErrorMessage(Object? error) {
    if (error is TimeoutException) {
      return error.message ?? 'Yêu cầu đã hết thời gian chờ.';
    }
    if (error is FormatException) {
      return 'Phản hồi API danh sách đơn vẫn sai định dạng JSON. Cần kiểm tra dữ liệu trả về từ Laravel.';
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return 'Phiên nhân viên đã hết hạn. Đăng nhập lại để tải đơn hàng.';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Không kết nối được máy chủ Laravel. Kiểm tra máy chủ và địa chỉ API rồi thử lại.';
      }
      if (error.error is FormatException) {
        return 'Máy chủ trả về dữ liệu đơn hàng không hợp lệ. Cần cập nhật backend Laravel rồi tải lại app.';
      }
      if (statusCode != null) {
        return 'Máy chủ từ chối tải đơn (HTTP $statusCode). Thử đăng xuất rồi đăng nhập lại.';
      }
      return 'Không tải được hàng đợi đơn hàng (${error.type.name}). Kiểm tra kết nối rồi thử lại.';
    }
    return 'Không tải được hàng đợi đơn hàng. Thử lại hoặc đăng nhập lại.';
  }
}

class _StaffQueueData {
  const _StaffQueueData({required this.roles, required this.orders});

  final List<String> roles;
  final List<LaundryOrderRecord> orders;
}

class _StaffOrderCard extends StatelessWidget {
  const _StaffOrderCard({
    required this.order,
    required this.nextStatuses,
    required this.isUpdating,
    required this.onInspect,
    required this.onTransition,
  });

  final LaundryOrderRecord order;
  final List<String> nextStatuses;
  final bool isUpdating;
  final VoidCallback onInspect;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    final isBooking = order.orderId == null;
    final actions = isBooking
        ? const ['Kiểm tra & tạo đơn']
        : nextStatuses
              .where((status) {
                if (order.deliveryMethod == 'Tại nhà' &&
                    (status == 'Đang giao' || status == 'Đã giao')) {
                  return order.canConfirmDelivery;
                }
                return true;
              })
              .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${order.orderNumber}',
                  style: AppTypography.title,
                ),
              ),
              Text(order.status, style: AppTypography.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isBooking
                ? 'Booking cần kiểm tra và nhận đồ'
                : 'Đơn hàng đang xử lý',
            style: AppTypography.bodySmall.copyWith(
              color: isBooking ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(order.lineDescription, style: AppTypography.bodyText),
          if (order.logisticsSummary case final logistics?) ...[
            const SizedBox(height: 4),
            Text(logistics, style: AppTypography.bodySmall),
          ],
          const SizedBox(height: 12),
          OrderConfirmationInfo(
            details: order.toDisplayDetails(),
            compact: true,
          ),
          const SizedBox(height: 8),
          Text(
            isBooking && !order.hasLaundryDetails
                ? 'Kiểm kê để báo giá'
                : FormatterUtils.formatVnd(order.totalVnd),
            style: AppTypography.title.copyWith(color: AppColors.primary),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions.map((status) {
                return OutlinedButton(
                  onPressed: isUpdating
                      ? null
                      : (isBooking ? onInspect : () => onTransition(status)),
                  child: Text(status),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueState extends StatelessWidget {
  const _QueueState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: AppTypography.bodyText),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
