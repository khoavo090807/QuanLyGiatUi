import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';
import 'package:app_quanly_giaiui/features/auth/data/staff_api_auth_repository.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_booking_repository.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_notification_repository.dart';
import 'package:app_quanly_giaiui/features/profile/screens/profile_screen.dart';
import 'package:app_quanly_giaiui/features/staff/screens/staff_delivery_confirmation_screen.dart';
import 'package:app_quanly_giaiui/features/staff/screens/staff_notifications_screen.dart';

class StaffOrderQueueScreen extends StatefulWidget {
  const StaffOrderQueueScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<StaffOrderQueueScreen> createState() => _StaffOrderQueueScreenState();
}

class _StaffOrderQueueScreenState extends State<StaffOrderQueueScreen> {
  static const _notificationSound = MethodChannel(
    'com.example.app_quanly_giaiui/notification_sound',
  );

  final _authRepository = AuthRepository();
  final _orderRepository = OrderRepository();
  final _staffRepository = StaffBookingRepository();
  final _notificationRepository = StaffNotificationRepository();
  late Future<_StaffQueueData> _queueFuture;
  Timer? _notificationCountTimer;
  final _unreadNotificationCount = ValueNotifier<int>(0);
  int? _latestNotificationId;
  bool _hasCheckedNotifications = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _queueFuture = _loadQueue();
    unawaited(_refreshUnreadNotificationCount());
    _notificationCountTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnreadNotificationCount(),
    );
  }

  @override
  void dispose() {
    _notificationCountTimer?.cancel();
    _unreadNotificationCount.dispose();
    super.dispose();
  }

  Future<void> _refreshUnreadNotificationCount() async {
    try {
      final page = await _notificationRepository.getPage();
      if (!mounted) return;
      final latestId = page.notifications.firstOrNull?.id;
      if (_hasCheckedNotifications &&
          latestId != null &&
          (_latestNotificationId == null ||
              latestId > _latestNotificationId!)) {
        unawaited(_playAssignmentNotificationSound());
      }
      _hasCheckedNotifications = true;
      if (latestId != null) _latestNotificationId = latestId;
      _unreadNotificationCount.value = page.unreadCount;
    } catch (_) {
      // Keep the last known unread count while the network is unavailable.
    }
  }

  Future<void> _playAssignmentNotificationSound() async {
    try {
      await _notificationSound.invokeMethod<void>('play', {
        'type': 'staff_assignment',
      });
    } on MissingPluginException {
      // The native notification tone is available on Android only.
    } on PlatformException catch (error) {
      debugPrint('Could not play assignment notification tone: $error');
    }
  }

  Future<void> _openNotifications() async {
    final selected = await Navigator.of(context).push<StaffNotification>(
      MaterialPageRoute(
        builder: (_) => StaffNotificationsScreen(
          unreadNotificationCount: _unreadNotificationCount,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.orderId == null && selected.bookingId != null) {
      await _openInspection(selected.bookingId!);
      return;
    }
    if (selected.orderId == null) return;

    List<LaundryOrderRecord> orders;
    try {
      orders = await _orderRepository.getStaffQueue();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở công việc: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    LaundryOrderRecord? targetOrder;
    for (final order in orders) {
      if (order.orderId == selected.orderId) {
        targetOrder = order;
        break;
      }
    }
    if (targetOrder == null) return;
    final orderToOpen = targetOrder;

    final statuses = _nextStatuses(orderToOpen).where((status) {
      if (status == 'Đã hủy') return false;
      return selected.type == 'staff_assignment_pickup' ||
          status == 'Đang giao' ||
          status == 'Đã giao';
    });
    final status = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Đơn ${orderToOpen.orderNumber}'),
        content: Text(
          statuses.isEmpty
              ? 'Trạng thái hiện tại: ${orderToOpen.status}. Công việc sẽ sẵn sàng xử lý khi đơn đến bước giao nhận.'
              : 'Trạng thái hiện tại: ${orderToOpen.status}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          ...statuses.map(
            (value) => FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: Text(value),
            ),
          ),
        ],
      ),
    );
    if (status != null && mounted) await _transition(orderToOpen, status);
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
      return _StaffQueueData(
        roles: roles,
        orders: const [],
        completedBookings: const [],
      );
    }
    final queueFuture = _orderRepository.getStaffQueue().timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        throw TimeoutException(
          'Máy chủ mất quá nhiều thời gian để tải đơn. Kiểm tra kết nối API Laravel rồi thử lại.',
        );
      },
    );
    final bookingHistoryFuture = _orderRepository
        .getStaffBookingHistory()
        .timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException(
            'Máy chủ mất quá nhiều thời gian để tải lịch sử Booking.',
          ),
        );
    final results = await Future.wait([queueFuture, bookingHistoryFuture]);
    return _StaffQueueData(
      roles: roles,
      orders: results[0],
      completedBookings: results[1],
    );
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
        order.isHomeDelivery ? ['Đang giao'] : ['Đang giao', 'Đã giao'],
      'Đang giao' => ['Đã giao'],
      _ => const [],
    };
  }

  List<LaundryOrderRecord> _ordersForTab(
    List<LaundryOrderRecord> orders,
    int tab,
  ) {
    final filtered = orders.where((order) {
      if (tab == 0) return order.orderId == null;
      if (order.orderId == null) return false;
      final isHistory = const {
        'Đã giao',
        'Hoàn thành',
        'Đã hủy',
        'Đã thanh toán',
      }.contains(order.status);
      return tab == 2 ? isHistory : !isHistory;
    }).toList();
    if (tab == 0) {
      filtered.sort(
        (left, right) => (left.appointment ?? DateTime(9999)).compareTo(
          right.appointment ?? DateTime(9999),
        ),
      );
    }
    return filtered;
  }

  Widget _queueTab(List<LaundryOrderRecord> orders, String emptyMessage) =>
      RefreshIndicator(
        onRefresh: _refresh,
        child: orders.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  SizedBox(
                    height: 220,
                    child: _QueueState(message: emptyMessage),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: orders.length + 1,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${orders.length} việc được phân công',
                        style: AppTypography.bodySmall,
                      ),
                    );
                  }
                  final order = orders[index - 1];
                  return _StaffOrderCard(
                    order: order,
                    nextStatuses: _nextStatuses(order),
                    isUpdating: _isUpdating,
                    onInspect: () => _openInspection(order.bookingId!),
                    onTransition: (status) => _transition(order, status),
                  );
                },
              ),
      );

  Widget _historyTabs(_StaffQueueData queue) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Đơn hàng (${_ordersForTab(queue.orders, 2).length})'),
              Tab(text: 'Booking (${queue.completedBookings.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _queueTab(
                _ordersForTab(queue.orders, 2),
                'Chưa có đơn hàng hoàn tất hoặc đã hủy.',
              ),
              _queueTab(
                queue.completedBookings,
                'Chưa có đặt lịch nào bạn đã nhận và kiểm tra thành công.',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _transition(LaundryOrderRecord order, String newStatus) async {
    if (newStatus == 'Đã giao' && order.isHomeDelivery) {
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
        if (newStatus == 'Đang giao' && order.isHomeDelivery) {
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
    final storedName = StaffApiAuthRepository.instance.user?['name'];
    final staffName = storedName is String && storedName.trim().isNotEmpty
        ? storedName.trim()
        : 'nhân viên';

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Xin chào, $staffName', style: AppTypography.heading3),
              const Text(
                'Chúc bạn một ngày làm việc hiệu quả!',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Thông báo công việc',
              onPressed: _openNotifications,
              icon: ValueListenableBuilder<int>(
                valueListenable: _unreadNotificationCount,
                builder: (context, count, _) => Badge(
                  isLabelVisible: count > 0,
                  smallSize: 10,
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
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
            return TabBarView(
              children: [
                _queueTab(
                  _ordersForTab(queue.orders, 0),
                  'Chưa có Booking nào cần tiếp nhận.',
                ),
                _queueTab(
                  _ordersForTab(queue.orders, 1),
                  'Không có đơn hàng nào đang xử lý.',
                ),
                _historyTabs(queue),
                const ProfileScreen(showAppBar: false),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: false,
              tabs: [
                const Tab(
                  icon: Icon(Icons.move_to_inbox_outlined),
                  text: 'Nhận đồ',
                ),
                const Tab(
                  icon: Icon(Icons.local_shipping_outlined),
                  text: 'Giao đồ',
                ),
                const Tab(
                  icon: Icon(Icons.check_circle_outline),
                  text: 'Hoàn thành',
                ),
                const Tab(icon: Icon(Icons.person_outline), text: 'Tài khoản'),
              ],
            ),
          ),
        ),
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
  const _StaffQueueData({
    required this.roles,
    required this.orders,
    required this.completedBookings,
  });

  final List<String> roles;
  final List<LaundryOrderRecord> orders;
  final List<LaundryOrderRecord> completedBookings;
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
    final List<String> actions;
    if (order.isCompletedBooking) {
      actions = const [];
    } else if (isBooking) {
      actions = const ['Kiểm tra và tạo đơn'];
    } else {
      actions = nextStatuses
          .where((status) {
            if (order.isHomeDelivery &&
                (status == 'Đang giao' || status == 'Đã giao')) {
              return order.canConfirmDelivery;
            }
            return true;
          })
          .toList(growable: false);
    }
    final String typeDescription;
    if (order.isCompletedBooking) {
      typeDescription = 'Đặt lịch đã tiếp nhận và kiểm tra thành công';
    } else if (isBooking) {
      typeDescription = 'Đặt lịch cần kiểm tra và nhận đồ';
    } else if (order.status == 'Đã hủy') {
      typeDescription = 'Đơn hàng đã hủy';
    } else if (const {
      'Đã giao',
      'Hoàn thành',
      'Đã thanh toán',
    }.contains(order.status)) {
      typeDescription = 'Đơn hàng đã hoàn tất';
    } else {
      typeDescription = 'Đơn hàng đang xử lý';
    }
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
            typeDescription,
            style: AppTypography.bodySmall.copyWith(
              color: isBooking ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (order.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              'Khách: ${order.customerName}${order.customerPhone?.isNotEmpty == true ? ' · ${order.customerPhone}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall,
            ),
          ],
          if (order.appointment != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hẹn: ${FormatterUtils.formatDateTime(order.appointment!)}',
              style: AppTypography.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Dịch vụ: ${order.lineDescription}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall,
          ),
          if (order.pickupMethod != null) ...[
            const SizedBox(height: 4),
            Text(
              'Nhận: ${order.pickupMethod}${order.pickupAddress?.isNotEmpty == true ? ' · ${order.pickupAddress}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall,
            ),
          ],
          if (order.deliveryMethod != null) ...[
            const SizedBox(height: 4),
            Text(
              'Trả: ${order.deliveryMethod}${order.deliveryAddress?.isNotEmpty == true ? ' · ${order.deliveryAddress}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall,
            ),
          ],
          if (isBooking &&
              !order.isCompletedBooking &&
              !order.hasLaundryDetails)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Kiểm tra để báo giá'),
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
