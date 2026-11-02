import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/staff_api_auth_repository.dart';

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
  bool _registeredForStaffApi = false;
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
    StaffApiAuthRepository.authRevision.addListener(_onStaffAuthChanged);

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
      _registeredForStaffApi = false;
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
    final staffAuth = StaffApiAuthRepository.instance;
    final token = _fcmToken;
    if (staffAuth.isSignedIn && token != null && token.isNotEmpty) {
      final rawAccountId = staffAuth.user?['id'];
      final accountId = rawAccountId is num ? rawAccountId.toInt() : null;
      if (accountId == null ||
          (_registeredTokenAccountId == accountId && _registeredForStaffApi)) {
        return;
      }
      try {
        await staffAuth.dio.post<void>(
          'staff/notifications/device-token',
          data: {'token': token, 'platform': 'android'},
          options: staffAuth.authorizedOptions(),
        );
        _registeredTokenAccountId = accountId;
        _registeredForStaffApi = true;
      } catch (error) {
        debugPrint('Could not register the staff FCM token: $error');
      }
      return;
    }

    if (_client.auth.currentUser == null || token == null) {
      _registeredTokenAccountId = null;
      _registeredForStaffApi = false;
      return;
    }

    try {
      final result = await _client.rpc('get_current_account_id');
      final accountId = result is num ? result.toInt() : null;
      if (accountId == null || token.isEmpty) return;
      if (_registeredTokenAccountId == accountId && !_registeredForStaffApi) {
        return;
      }

      await _client.rpc(
        'register_push_device_token',
        params: {'p_token': token},
      );
      _registeredTokenAccountId = accountId;
      _registeredForStaffApi = false;
    } catch (error) {
      debugPrint('Could not register the FCM device token: $error');
    }
  }

  void _onStaffAuthChanged() => _registerTokenForCurrentUser();

  /// Remove this installation's token before signing out, so it stops receiving
  /// private notifications for the account that is being left.
  Future<void> unregisterCurrentDevice() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final token = _fcmToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final staffAuth = StaffApiAuthRepository.instance;
        if (staffAuth.isSignedIn) {
          await staffAuth.dio.delete<void>(
            'staff/notifications/device-token',
            data: {'token': token},
            options: staffAuth.authorizedOptions(),
          );
        } else if (_client.auth.currentUser != null) {
          await _client.rpc(
            'unregister_push_device_token',
            params: {'p_token': token},
          );
        }
      }
    } catch (error) {
      debugPrint('Could not unregister the FCM device token: $error');
    } finally {
      _registeredTokenAccountId = null;
      _registeredForStaffApi = false;
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    StaffApiAuthRepository.authRevision.removeListener(_onStaffAuthChanged);
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _authSubscription = null;
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _isInitialized = false;
  }
}
