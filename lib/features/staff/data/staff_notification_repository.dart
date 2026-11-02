import 'package:app_quanly_giaiui/features/auth/data/staff_api_auth_repository.dart';

class StaffNotification {
  const StaffNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.sentAt,
    required this.isRead,
    this.orderId,
    this.bookingId,
    this.type,
  });

  final int id;
  final String title;
  final String message;
  final DateTime sentAt;
  final bool isRead;
  final int? orderId;
  final int? bookingId;
  final String? type;

  factory StaffNotification.fromJson(Map<String, dynamic> json) =>
      StaffNotification(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        sentAt: DateTime.parse(json['sent_at'] as String).toLocal(),
        isRead: json['is_read'] as bool? ?? false,
        orderId: (json['order_id'] as num?)?.toInt(),
        bookingId: (json['booking_id'] as num?)?.toInt(),
        type: json['type'] as String?,
      );
}

class StaffNotificationPage {
  const StaffNotificationPage({
    required this.notifications,
    required this.unreadCount,
    required this.page,
    required this.lastPage,
  });

  final List<StaffNotification> notifications;
  final int unreadCount;
  final int page;
  final int lastPage;
}

class StaffNotificationRepository {
  final _auth = StaffApiAuthRepository.instance;

  Future<StaffNotificationPage> getPage({int page = 1}) async {
    final response = await _auth.dio.get<Map<String, dynamic>>(
      'staff/notifications',
      queryParameters: {'page': page, 'per_page': 20},
      options: _auth.authorizedOptions(),
    );
    final payload = response.data;
    final data = payload?['data'];
    final meta = payload?['meta'];
    if (data is! List || meta is! Map) {
      throw const FormatException('Dữ liệu thông báo nhân viên không hợp lệ.');
    }
    return StaffNotificationPage(
      notifications: data
          .whereType<Map>()
          .map(
            (row) => StaffNotification.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      unreadCount: (meta['unread_count'] as num?)?.toInt() ?? 0,
      page: (meta['page'] as num?)?.toInt() ?? page,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? page,
    );
  }

  Future<int> getUnreadCount() async {
    final response = await _auth.dio.get<Map<String, dynamic>>(
      'staff/notifications/unread-count',
      options: _auth.authorizedOptions(),
    );
    final count = response.data?['data']?['unread_count'];
    if (count is! num) {
      throw const FormatException('Số lượng thông báo chưa đọc không hợp lệ.');
    }
    return count.toInt();
  }

  Future<void> markRead(int id, {required bool read}) async {
    await _auth.dio.patch<void>(
      'staff/notifications/$id/${read ? 'read' : 'unread'}',
      options: _auth.authorizedOptions(),
    );
  }

  Future<void> markAllRead() async {
    await _auth.dio.patch<void>(
      'staff/notifications/read-all',
      options: _auth.authorizedOptions(),
    );
  }

  Future<void> markManyRead(Iterable<int> ids, {required bool read}) async {
    await _auth.dio.patch<void>(
      'staff/notifications/${read ? 'read' : 'unread'}',
      data: {'ids': ids.toList(growable: false)},
      options: _auth.authorizedOptions(),
    );
  }

  Future<void> delete(int id) async {
    await _auth.dio.delete<void>(
      'staff/notifications/$id',
      options: _auth.authorizedOptions(),
    );
  }

  Future<void> deleteMany(Iterable<int> ids) async {
    await _auth.dio.delete<void>(
      'staff/notifications/selected',
      data: {'ids': ids.toList(growable: false)},
      options: _auth.authorizedOptions(),
    );
  }
}
