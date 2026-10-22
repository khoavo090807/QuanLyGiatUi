import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:app_quanly_giaiui/features/auth/data/staff_api_auth_repository.dart';

class StaffBookingRepository {
  StaffBookingRepository({Dio? dio})
    : _dio = dio ?? StaffApiAuthRepository.instance.dio;

  final Dio _dio;

  Future<List<Map<String, dynamic>>> getStaffOrders() async {
    final payload = await _getJsonMap('staff/orders');
    final data = payload['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
    String? reason,
  }) async {
    await _dio.patch<void>(
      'staff/orders/$orderId/status',
      data: {'status': status, 'reason': ?reason},
      options: await _authorizedOptions(),
    );
  }

  Future<List<Map<String, dynamic>>> getAssignedBookings() async {
    final payload = await _getJsonMap('staff/bookings');
    final data = payload['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getBooking(int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'staff/bookings/$bookingId',
      options: await _authorizedOptions(),
    );
    return _dataObject(response.data);
  }

  Future<Map<String, dynamic>> estimate(
    int bookingId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'staff/bookings/$bookingId/estimate',
      data: payload,
      options: await _authorizedOptions(),
    );
    return _dataObject(response.data);
  }

  Future<Map<String, dynamic>> confirm(
    int bookingId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'staff/bookings/$bookingId/confirm',
      data: payload,
      options: await _authorizedOptions(),
    );
    return _dataObject(response.data);
  }

  Future<Map<String, dynamic>> saveDraft(
    int bookingId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'staff/bookings/$bookingId/draft',
      data: payload,
      options: await _authorizedOptions(),
    );
    return _dataObject(response.data);
  }

  Future<Options> _authorizedOptions() async {
    return StaffApiAuthRepository.instance.authorizedOptions();
  }

  Future<Map<String, dynamic>> _getJsonMap(String path) async {
    final response = await _dio.get<List<int>>(
      path,
      options: (await _authorizedOptions()).copyWith(
        responseType: ResponseType.bytes,
      ),
    );
    final body = utf8.decode(
      response.data ?? const <int>[],
      allowMalformed: true,
    );
    // Repair only unambiguous serialization defects before parsing. Parsing
    // first and catching FormatException makes Flutter's debugger stop on
    // recoverable responses when it is configured to pause on thrown errors.
    final normalizedBody = _normalizeMalformedUnicodeEscapes(body)
        .replaceAllMapped(
          RegExp(
            r'("(?:\\.|[^"\\])*"|[}\]]|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)(?=\s*"(?:\\.|[^"\\])*"\s*:)',
          ),
          (match) => '${match[1]},',
        )
        .replaceAllMapped(
          RegExp(r'(\{|\[|,)(\s*)"?([A-Za-z_][A-Za-z0-9_]*)"?(\s*:)'),
          (match) => '${match[1]}${match[2]}"${match[3]}"${match[4]}',
        );
    final decoded = jsonDecode(normalizedBody);
    if (decoded is! Map) {
      throw const FormatException(
        'Máy chủ trả về dữ liệu không phải JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _normalizeMalformedUnicodeEscapes(String value) {
    final result = StringBuffer();
    var index = 0;

    while (index < value.length) {
      if (value.codeUnitAt(index) == 0x5c &&
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) == 0x75) {
        var precedingSlashes = 0;
        for (
          var cursor = index - 1;
          cursor >= 0 && value.codeUnitAt(cursor) == 0x5c;
          cursor--
        ) {
          precedingSlashes++;
        }

        if (precedingSlashes.isEven) {
          var end = index + 2;
          while (end < value.length &&
              end < index + 6 &&
              _isHexDigit(value.codeUnitAt(end))) {
            end++;
          }
          final digitCount = end - index - 2;
          if (digitCount < 4) {
            if (digitCount == 0) {
              result.write('\uFFFD');
            } else {
              result
                ..write(r'\u')
                ..write('0' * (4 - digitCount))
                ..write(value.substring(index + 2, end));
            }
            index = end;
            continue;
          }
        }
      }

      result.write(value[index]);
      index++;
    }

    return result.toString();
  }

  bool _isHexDigit(int value) =>
      (value >= 0x30 && value <= 0x39) ||
      (value >= 0x41 && value <= 0x46) ||
      (value >= 0x61 && value <= 0x66);

  Map<String, dynamic> _dataObject(Map<String, dynamic>? response) {
    final data = response?['data'];
    if (data is! Map) {
      throw const FormatException(
        'Máy chủ trả về dữ liệu Booking không hợp lệ.',
      );
    }
    return Map<String, dynamic>.from(data);
  }
}
