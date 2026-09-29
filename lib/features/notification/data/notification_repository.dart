import 'package:supabase_flutter/supabase_flutter.dart';

class LaundryNotification {
  const LaundryNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.sentAt,
    required this.isRead,
    this.orderId,
    this.type,
  });

  final int id;
  final String title;
  final String message;
  final DateTime sentAt;
  final bool isRead;
  final int? orderId;
  final String? type;

  factory LaundryNotification.fromJson(Map<String, dynamic> json) {
    return LaundryNotification(
      id: (json['thongbaoid'] as num).toInt(),
      title: json['tieude'] as String,
      message: json['noidung'] as String,
      sentAt: DateTime.parse(json['thoigiangui'] as String),
      isRead: json['dadoc'] as bool,
      orderId: (json['donhangid'] as num?)?.toInt(),
      type: json['loaithongbao'] as String?,
    );
  }
}

class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<LaundryNotification>> getNotifications() async {
    final rows = await _client
        .from('thongbao')
        .select(
          'thongbaoid,tieude,noidung,thoigiangui,dadoc,donhangid,loaithongbao',
        )
        .order('thoigiangui', ascending: false);

    return (rows as List<dynamic>)
        .map((row) => LaundryNotification.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> markRead(int notificationId) async {
    await _client
        .from('thongbao')
        .update({'dadoc': true})
        .eq('thongbaoid', notificationId);
  }

  Future<void> markAllRead() async {
    await _client.from('thongbao').update({'dadoc': true}).eq('dadoc', false);
  }
}
