import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/navigation/app_router.dart';
import 'package:app_quanly_giaiui/features/notification/data/notification_repository.dart';
import 'package:app_quanly_giaiui/features/notification/services/notification_service.dart';
import 'package:app_quanly_giaiui/features/notification/widgets/notification_popup.dart';

class NotificationOverlay extends StatefulWidget {
  final Widget child;

  const NotificationOverlay({required this.child, super.key});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  final _service = NotificationService.instance;
  final _notifications = <LaundryNotification>[];
  final _queuedNotificationIds = <int>{};
  OverlayEntry? _currentEntry;
  StreamSubscription<LaundryNotification>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _service.onNewNotification.listen(_handleNewNotification);
  }

  Future<void> _handleNewNotification(LaundryNotification notification) async {
    if (!_queuedNotificationIds.add(notification.id)) return;
    await _service.playNotificationSound();

    if (!mounted) return;
    setState(() => _notifications.add(notification));
    if (_currentEntry == null) _showNotification(notification);
  }

  void _showNotification(LaundryNotification notification) {
    final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotification(notification);
      });
      return;
    }

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: SafeArea(
          child: NotificationPopup(
            notification: notification,
            onDismiss: () {
              _currentEntry?.remove();
              _currentEntry = null;
              _notifications.remove(notification);
              _queuedNotificationIds.remove(notification.id);

              if (_notifications.isNotEmpty) {
                _showNotification(_notifications.first);
              }
            },
          ),
        ),
      ),
    );

    overlay.insert(_currentEntry!);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _currentEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
