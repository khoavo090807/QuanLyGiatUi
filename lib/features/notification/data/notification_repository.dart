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
    // Handle both lowercase (from view select) and capitalized (from realtime table insert)
    return LaundryNotification(
      id: (json['thongbaoid'] ?? json['ThongBaoID'] as num).toInt(),
      title: (json['tieude'] ?? json['TieuDe']) as String,
      message: (json['noidung'] ?? json['NoiDung']) as String,
      sentAt: DateTime.parse(
        (json['thoigiangui'] ?? json['ThoiGianGui']) as String,
      ),
      isRead: (json['dadoc'] ?? json['DaDoc']) as bool,
      orderId: ((json['donhangid'] ?? json['DonHangID']) as num?)?.toInt(),
      type: (json['loaithongbao'] ?? json['LoaiThongBao']) as String?,
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

  Future<int> getUnreadCount() async {
    final rows = await _client
        .from('thongbao')
        .select('thongbaoid')
        .eq('dadoc', false);
    return (rows as List<dynamic>).length;
  }

  Future<void> markRead(int notificationId) async {
    await _client.rpc(
      'mark_notifications_read',
      params: {'p_notification_ids': [notificationId]},
    );
  }

  Future<void> markAllRead() async {
    await _client.rpc('mark_notifications_read');
  }

  Future<void> markManyRead(Iterable<int> notificationIds) async {
    final ids = notificationIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _client.rpc(
      'mark_notifications_read',
      params: {'p_notification_ids': ids},
    );
  }

}
