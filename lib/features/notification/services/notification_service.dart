import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _client = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  String? _fcmToken;
  int? _registeredTokenAccountId;
  bool _isInitialized = false;
  static const _pushChannel = AndroidNotificationChannel(
    'laundry_updates',
    'Cập nhật đơn hàng và thông báo',
    description: 'Thông báo mới về đơn hàng và tài khoản của bạn.',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _initializeFirebaseMessaging();
    }

    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _registerTokenForCurrentUser();
    });

    _isInitialized = true;
    await _registerTokenForCurrentUser();
  }

  Future<void> _initializeFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(settings: initializationSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_pushChannel);

    _fcmToken = await messaging.getToken();
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundPush,
    );
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      _registeredTokenAccountId = null;
      _registerTokenForCurrentUser();
    });
  }

  Future<void> _showForegroundPush(RemoteMessage message) async {
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title == null && body == null) return;

    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title ?? 'Thông báo mới',
      body: body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'laundry_updates',
          'Cập nhật đơn hàng và thông báo',
          channelDescription: 'Thông báo mới về đơn hàng và tài khoản của bạn.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _registerTokenForCurrentUser() async {
    if (_client.auth.currentUser == null || _fcmToken == null) {
      _registeredTokenAccountId = null;
      return;
    }

    try {
      final result = await _client.rpc('get_current_account_id');
      final accountId = result is num ? result.toInt() : null;
      final token = _fcmToken;
      if (accountId == null || token == null || token.isEmpty) return;
      if (_registeredTokenAccountId == accountId) return;

      await _client.rpc(
        'register_push_device_token',
        params: {'p_token': token},
      );
      _registeredTokenAccountId = accountId;
    } catch (error) {
      debugPrint('Could not register the FCM device token: $error');
    }
  }

  /// Remove this installation's token before signing out, so it stops receiving
  /// private notifications for the account that is being left.
  Future<void> unregisterCurrentDevice() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final token = _fcmToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _client.rpc(
          'unregister_push_device_token',
          params: {'p_token': token},
        );
      }
    } catch (error) {
      debugPrint('Could not unregister the FCM device token: $error');
    } finally {
      _registeredTokenAccountId = null;
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _authSubscription = null;
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _isInitialized = false;
  }
}
