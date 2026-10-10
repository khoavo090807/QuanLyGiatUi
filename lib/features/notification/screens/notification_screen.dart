import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/notification/data/notification_repository.dart';
import 'package:app_quanly_giaiui/features/messaging/data/message_repository.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({required this.unreadNotificationCount, super.key});

  final ValueNotifier<int> unreadNotificationCount;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _repository = NotificationRepository();
  late Future<List<LaundryNotification>> _notificationsFuture;
  final Set<int> _selectedNotificationIds = {};
  List<int> _loadedNotificationIds = [];
  bool _isBusy = false;
  RealtimeChannel? _realtimeChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _loadNotifications();
    _realtimeChannel = Supabase.instance.client
        .channel('notification-list:${Supabase.instance.client.auth.currentUser?.id ?? 'anonymous'}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'ThongBao', callback: (_) => _refresh())
        .subscribe();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<List<LaundryNotification>> _loadNotifications() async {
    final notifications = await _repository.getNotifications();
    if (mounted) {
      _loadedNotificationIds = notifications
          .map((notification) => notification.id)
          .toList(growable: false);
      _selectedNotificationIds.retainAll(_loadedNotificationIds);
      widget.unreadNotificationCount.value = notifications
          .where((notification) => !notification.isRead)
          .length;
    }
    return notifications;
  }

  Future<void> _refresh() async {
    final future = _loadNotifications();
    setState(() {
      _notificationsFuture = future;
    });
    await future;
  }

  Future<void> _markAllRead() async {
    setState(() => _isBusy = true);
    try {
      await _repository.markAllRead();
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cập nhật thông báo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _markSelectedRead() async {
    if (_selectedNotificationIds.isEmpty) return;
    setState(() => _isBusy = true);
    try {
      await _repository.markManyRead(_selectedNotificationIds);
      _selectedNotificationIds.clear();
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cập nhật thông báo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _markSelectedUnread() async {
    if (_selectedNotificationIds.isEmpty) return;
    await _runBulk(() => _repository.markManyUnread(_selectedNotificationIds));
  }

  Future<void> _deleteSelected() async {
    if (_selectedNotificationIds.isEmpty) return;
    final confirmed = await _confirmDelete(_selectedNotificationIds.length);
    if (!confirmed || !mounted) return;
    await _runBulk(() => _repository.deleteMany(_selectedNotificationIds));
  }

  Future<void> _runBulk(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
      _selectedNotificationIds.clear();
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể cập nhật thông báo.')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _confirmDelete(int count) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Xóa thông báo?'),
      content: Text(count == 1 ? 'Thông báo này sẽ bị xóa.' : 'Xóa $count thông báo đã chọn?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa'))],
    ),
  ) ?? false;

  Future<void> _handleNotificationAction(LaundryNotification notification, String action) async {
    try {
      if (action == 'delete') {
        if (!await _confirmDelete(1) || !mounted) return;
        await _repository.deleteNotification(notification.id);
      } else if (action == 'unread') {
        await _repository.markUnread(notification.id);
      } else {
        await _repository.markRead(notification.id);
      }
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể cập nhật thông báo.')));
    }
  }

  void _toggleSelection(int notificationId, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _selectedNotificationIds.add(notificationId);
      } else {
        _selectedNotificationIds.remove(notificationId);
      }
    });
  }

  void _toggleAllSelection() {
    setState(() {
      if (_selectedNotificationIds.length == _loadedNotificationIds.length) {
        _selectedNotificationIds.clear();
      } else {
        _selectedNotificationIds
          ..clear()
          ..addAll(_loadedNotificationIds);
      }
    });
  }

  Future<void> _openNotification(LaundryNotification notification) async {
    if (!notification.isRead) {
      try {
        await _repository.markRead(notification.id);
        await _refresh();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể cập nhật thông báo.')),
          );
        }
      }
    }

    if (mounted && notification.messageId != null) {
      try {
        final thread = await MessageRepository().getThreadForMessage(notification.messageId!);
        if (mounted) context.pushNamed(AppRoutes.chat, extra: thread);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được cuộc trò chuyện.')));
      }
    } else if (mounted && notification.orderId != null) {
      context.pushNamed(
        AppRoutes.trackingDetail,
        pathParameters: {'id': notification.orderId.toString()},
      );
    } else if (mounted && _isOrderOrBookingNotification(notification)) {
      try {
        final bookingId = await _repository.findBookingId(
          notification.message,
          bookingId: notification.bookingId,
        );
        if (!mounted) return;
        if (bookingId != null) {
          context.pushNamed(
            AppRoutes.trackingDetail,
            pathParameters: {'id': 'booking_$bookingId'},
          );
        } else {
          context.pushNamed(AppRoutes.myOrders);
        }
      } catch (_) {
        if (mounted) context.pushNamed(AppRoutes.myOrders);
      }
    }
  }

  bool _isOrderOrBookingNotification(LaundryNotification notification) {
    final type = (notification.type ?? '').toLowerCase();
    return type.contains('booking') || type.contains('order') ||
        RegExp(r'\bBK-').hasMatch(notification.message);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  String _timeLabel(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) return 'Vừa xong';
    if (difference.inHours < 1) return '${difference.inMinutes} phút trước';
    if (difference.inDays < 1) return '${difference.inHours} giờ trước';
    if (difference.inDays < 7) return '${difference.inDays} ngày trước';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.notifications),
        actions: [
          Tooltip(
            message: 'Chọn tất cả thông báo',
            child: Checkbox(
              value:
                  _selectedNotificationIds.isNotEmpty &&
                  _selectedNotificationIds.length ==
                      _loadedNotificationIds.length,
              tristate:
                  _selectedNotificationIds.isNotEmpty &&
                  _selectedNotificationIds.length <
                      _loadedNotificationIds.length,
              onChanged: _isBusy || _loadedNotificationIds.isEmpty
                  ? null
                  : (_) => _toggleAllSelection(),
            ),
          ),
          IconButton(
            tooltip: 'Đánh dấu đã đọc',
            onPressed: _isBusy || _selectedNotificationIds.isEmpty
                ? null
                : _markSelectedRead,
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
          IconButton(
            tooltip: 'Đánh dấu chưa đọc',
            onPressed: _isBusy || _selectedNotificationIds.isEmpty ? null : _markSelectedUnread,
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'Xóa thông báo đã chọn',
            onPressed: _isBusy || _selectedNotificationIds.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Đánh dấu tất cả đã đọc',
            onPressed: _isBusy ? null : _markAllRead,
            icon: _isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
          ),
        ],
      ),
      body: FutureBuilder<List<LaundryNotification>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _NotificationState(
              icon: Icons.cloud_off_outlined,
              text: 'Không tải được thông báo.',
              action: TextButton(
                onPressed: () => setState(() {
                  _notificationsFuture = _loadNotifications();
                }),
                child: const Text('Thử lại'),
              ),
            );
          }

          final notifications = snapshot.data ?? const <LaundryNotification>[];
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  _NotificationState(
                    icon: Icons.notifications_off_outlined,
                    text: AppStrings.noNotifications,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: notifications.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                final isSelected = _selectedNotificationIds.contains(
                  notification.id,
                );
                return ListTile(
                  tileColor: isSelected
                      ? AppColors.primaryLight
                      : notification.isRead
                      ? AppColors.surface
                      : AppColors.primaryExtraLight,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: notification.isRead
                        ? AppColors.border
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    child: Icon(_iconFor(notification.type)),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    PopupMenuButton<String>(
                      enabled: !_isBusy,
                      onSelected: (action) => _handleNotificationAction(notification, action),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: notification.isRead ? 'unread' : 'read', child: Text(notification.isRead ? 'Đánh dấu chưa đọc' : 'Đánh dấu đã đọc')),
                        const PopupMenuItem(value: 'delete', child: Text('Xóa thông báo')),
                      ],
                    ),
                    Checkbox(
                      value: isSelected,
                      onChanged: _isBusy ? null : (selected) => _toggleSelection(notification.id, selected),
                    ),
                  ]),
                  title: Text(
                    notification.title,
                    style: AppTypography.title.copyWith(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notification.message),
                        const SizedBox(height: 6),
                        Text(
                          _timeLabel(notification.sentAt),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () {
                    if (_selectedNotificationIds.isNotEmpty) {
                      _toggleSelection(notification.id, !isSelected);
                    } else {
                      _openNotification(notification);
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String? type) {
    final normalized = (type ?? '').toLowerCase();
    if (normalized.contains('message')) return Icons.chat_bubble_outline;
    if (normalized.contains('giao')) return Icons.local_shipping_outlined;
    if (normalized.contains('thanh')) return Icons.payments_outlined;
    return Icons.local_laundry_service_outlined;
  }
}

class _NotificationState extends StatelessWidget {
  const _NotificationState({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            text,
            style: AppTypography.bodyText.copyWith(color: AppColors.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
