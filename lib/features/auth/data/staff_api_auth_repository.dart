import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StaffApiAuthRepository {
  StaffApiAuthRepository._() {
    dio = Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment(
          'STAFF_API_BASE_URL',
          defaultValue: 'https://sky-laundry.vercel.app/api/v1/',
        ),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {'Accept': 'application/json'},
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              error.requestOptions.headers.containsKey('Authorization')) {
            await clearLocalSession();
          }
          handler.next(error);
        },
      ),
    );
  }

  static final instance = StaffApiAuthRepository._();
  static final ValueNotifier<int> authRevision = ValueNotifier(0);

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'staff_api_access_token';
  static const _userKey = 'staff_api_user';

  late final Dio dio;

  String? _token;
  Map<String, dynamic>? _user;

  bool get isSignedIn => _token != null && _token!.isNotEmpty;
  List<String> get roles =>
      (_user?['roles'] as List? ?? const []).whereType<String>().toList();
  Map<String, dynamic>? get user => _user;

  Future<void> initialize() async {
    _token = await _storage.read(key: _tokenKey);
    final savedUser = await _storage.read(key: _userKey);
    if (_token == null || _token!.isEmpty) {
      _user = null;
      await _storage.delete(key: _userKey);
    } else if (savedUser != null) {
      try {
        _user = Map<String, dynamic>.from(jsonDecode(savedUser) as Map);
      } catch (_) {
        await clearLocalSession();
      }
    }
    authRevision.value++;
  }

  Future<void> login({required String email, required String password}) async {
    final response = await dio.post<Map<String, dynamic>>(
      'staff/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    final data = response.data?['data'];
    if (data is! Map ||
        data['access_token'] is! String ||
        data['user'] is! Map) {
      throw const FormatException(
        'Máy chủ trả về phiên đăng nhập không hợp lệ.',
      );
    }
    _token = data['access_token'] as String;
    _user = Map<String, dynamic>.from(data['user'] as Map);
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: _userKey, value: _encodeUser(_user!));
    authRevision.value++;
  }

  Options authorizedOptions() {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const StaffApiAuthException(
        'Phiên nhân viên hết hạn. Vui lòng đăng nhập lại.',
      );
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> signOut() async {
    try {
      if (isSignedIn) {
        await dio.post<void>('staff/auth/logout', options: authorizedOptions());
      }
    } catch (_) {
      // Local logout must still work when the server is unreachable.
    } finally {
      await clearLocalSession();
    }
  }

  Future<void> clearLocalSession() async {
    _token = null;
    _user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    authRevision.value++;
  }

  String _encodeUser(Map<String, dynamic> user) => jsonEncode(user);
}

class StaffApiAuthException implements Exception {
  const StaffApiAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
