import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/features/notification/data/notification_repository.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _soundChannel = MethodChannel(
    'com.example.app_quanly_giaiui/notification_sound',
  );

  final _client = Supabase.instance.client;
  final _newNotificationController =
      StreamController<LaundryNotification>.broadcast();

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _pollTimer;
  int? _subscribedTaiKhoanId;
  bool _isInitialized = false;
  bool _isPolling = false;
  final _notificationRepository = NotificationRepository();
  final Set<int> _deliveredNotificationIds = <int>{};

  Stream<LaundryNotification> get onNewNotification =>
      _newNotificationController.stream;

  void showInApp(LaundryNotification notification) {
    _newNotificationController.add(notification);
  }

  static const String _notificationEnabledKey = 'notification_enabled';
  bool _notificationEnabled = true;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _notificationEnabled = prefs.getBool(_notificationEnabledKey) ?? true;

    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _subscribeForCurrentUser();
    });

    _isInitialized = true;
    await _subscribeForCurrentUser();
  }

  Future<void> _subscribeForCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _pollTimer?.cancel();
      _pollTimer = null;
      await _unsubscribeCurrentChannel();
      return;
    }

    int? taikhoanId;
    try {
      final result = await _client.rpc('get_current_account_id');
      taikhoanId = result is num ? result.toInt() : null;
      if (taikhoanId == null) {
        debugPrint('Realtime notifications not started: no application account id.');
        return;
      }
    } catch (e) {
      debugPrint('Failed to get taikhoanid: $e');
      return;
    }

    if (_subscribedTaiKhoanId == taikhoanId && _channel != null) {
      return;
    }

    await _unsubscribeCurrentChannel();

    // Record notifications already in the inbox so opening the app never
    // replays old notifications as new popups.
    try {
      final existing = await _notificationRepository.getRecentNotifications();
      _deliveredNotificationIds.addAll(existing.map((item) => item.id));
    } catch (e) {
      debugPrint('Could not load the initial notification snapshot: $e');
    }

    _channel = _client
        .channel('notifications:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ThongBao',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'TaiKhoanID',
            value: taikhoanId,
          ),
          callback: (payload) {
            try {
              _deliverIfNew(LaundryNotification.fromJson(payload.newRecord));
            } catch (e) {
              debugPrint('Could not parse a realtime notification: $e');
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('Realtime notification channel connected.');
          } else if (error != null) {
            debugPrint('Realtime notification channel error: $error');
          }
        });

    _subscribedTaiKhoanId = taikhoanId;
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollForNewNotifications(),
    );
  }

  Future<void> _pollForNewNotifications() async {
    if (_isPolling || _subscribedTaiKhoanId == null) return;
    _isPolling = true;
    try {
      final latest = await _notificationRepository.getRecentNotifications();
      for (final notification in latest.reversed) {
        _deliverIfNew(notification);
      }
    } catch (e) {
      debugPrint('Could not check for new notifications: $e');
    } finally {
      _isPolling = false;
    }
  }

  void _deliverIfNew(LaundryNotification notification) {
    if (!_deliveredNotificationIds.add(notification.id)) return;
    if (_deliveredNotificationIds.length > 500) {
      _deliveredNotificationIds.remove(_deliveredNotificationIds.first);
    }
    _newNotificationController.add(notification);
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    await _unsubscribeCurrentChannel();
    await _newNotificationController.close();
    _isInitialized = false;
  }

  Future<void> _unsubscribeCurrentChannel() async {
    await _channel?.unsubscribe();
    _channel = null;
    _subscribedTaiKhoanId = null;
    _deliveredNotificationIds.clear();
  }

  Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey) ?? true;
  }

  Future<void> setNotificationEnabled(bool enabled) async {
    _notificationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);
  }

  bool get notificationEnabled => _notificationEnabled;

  Future<void> playNotificationSound({String? notificationType}) async {
    if (!_notificationEnabled) return;

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _soundChannel.invokeMethod<void>(
          'play',
          {'type': notificationType},
        );
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (e) {
      debugPrint('Failed to play notification sound: $e');
    }
  }
}
