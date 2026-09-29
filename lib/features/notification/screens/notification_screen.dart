import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/notification/data/notification_repository.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _repository = NotificationRepository();
  late Future<List<LaundryNotification>> _notificationsFuture;
  bool _isMarkingAllRead = false;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _repository.getNotifications();
  }

  Future<void> _refresh() async {
    final future = _repository.getNotifications();
    setState(() {
      _notificationsFuture = future;
    });
    await future;
  }

  Future<void> _markAllRead() async {
    setState(() => _isMarkingAllRead = true);
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
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
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

    if (mounted && notification.orderId != null) {
      context.pushNamed(
        AppRoutes.trackingDetail,
        pathParameters: {'id': notification.orderId.toString()},
      );
    }
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
          IconButton(
            tooltip: 'Đánh dấu tất cả đã đọc',
            onPressed: _isMarkingAllRead ? null : _markAllRead,
            icon: _isMarkingAllRead
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
                  _notificationsFuture = _repository.getNotifications();
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
                return ListTile(
                  tileColor: notification.isRead
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
                  onTap: () => _openNotification(notification),
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
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}
