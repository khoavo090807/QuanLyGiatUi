import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/utils/database_timestamp.dart';

class LaundryNotification {
  const LaundryNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.sentAt,
    required this.isRead,
    this.orderId,
    this.messageId,
    this.bookingId,
    this.type,
  });

  final int id;
  final String title;
  final String message;
  final DateTime sentAt;
  final bool isRead;
  final int? orderId;
  final int? messageId;
  final int? bookingId;
  final String? type;

  factory LaundryNotification.fromJson(Map<String, dynamic> json) {
    // Handle both lowercase (from view select) and capitalized (from realtime table insert)
    return LaundryNotification(
      id: (json['thongbaoid'] ?? json['ThongBaoID'] as num).toInt(),
      title: (json['tieude'] ?? json['TieuDe']) as String,
      message: (json['noidung'] ?? json['NoiDung']) as String,
      sentAt: parseDatabaseTimestamp(
        (json['thoigiangui'] ?? json['ThoiGianGui']) as String,
      ),
      isRead: (json['dadoc'] ?? json['DaDoc']) as bool,
      orderId: ((json['donhangid'] ?? json['DonHangID']) as num?)?.toInt(),
      messageId: ((json['tinnhanid'] ?? json['TinNhanID']) as num?)?.toInt(),
      bookingId: ((json['bookingid'] ?? json['BookingID']) as num?)?.toInt(),
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
          'thongbaoid,tieude,noidung,thoigiangui,dadoc,donhangid,loaithongbao,tinnhanid,bookingid',
        )
        .order('thoigiangui', ascending: false);

    return (rows as List<dynamic>)
        .map((row) => LaundryNotification.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<LaundryNotification>> getRecentNotifications({int limit = 20}) async {
    final rows = await _client
        .from('thongbao')
        .select(
          'thongbaoid,tieude,noidung,thoigiangui,dadoc,donhangid,loaithongbao,tinnhanid,bookingid',
        )
        .order('thoigiangui', ascending: false)
        .limit(limit);

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

  Future<int> getUnreadMessageCount() async {
    final rows = await _client
        .from('thongbao')
        .select('thongbaoid')
        .eq('loaithongbao', 'new_message')
        .eq('dadoc', false);
    return (rows as List<dynamic>).length;
  }

  Future<void> markRead(int notificationId) async {
    await _client.rpc(
      'mark_notifications_read',
      params: {'p_notification_ids': [notificationId]},
    );
  }

  Future<int?> findBookingId(
    String notificationMessage, {
    int? bookingId,
  }) async {
    if (bookingId != null) return bookingId;
    final match = RegExp(r'\bBK-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*')
        .firstMatch(notificationMessage);
    final bookingNumber = match?.group(0);
    if (bookingNumber == null) return null;

    final row = await _client
        .from('Booking')
        .select('BookingID')
        .eq('MaBooking', bookingNumber)
        .maybeSingle();
    return (row?['BookingID'] as num?)?.toInt();
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

  Future<void> markUnread(int notificationId) async {
    await _client.from('thongbao').update({'dadoc': false}).eq('thongbaoid', notificationId);
  }

  Future<void> markManyUnread(Iterable<int> notificationIds) async {
    final ids = notificationIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _client.from('thongbao').update({'dadoc': false}).inFilter('thongbaoid', ids);
  }

  Future<void> deleteMany(Iterable<int> notificationIds) async {
    final ids = notificationIds.toList(growable: false);
    if (ids.isEmpty) return;
    await _client.from('ThongBao').delete().inFilter('ThongBaoID', ids);
  }

  Future<void> deleteNotification(int notificationId) async {
    await _client.from('ThongBao').delete().eq('ThongBaoID', notificationId);
  }

}
