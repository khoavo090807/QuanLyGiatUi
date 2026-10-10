import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/utils/database_timestamp.dart';

class ChatThread {
  const ChatThread({
    required this.peerAccountId,
    required this.currentAccountId,
    required this.title,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.isStaff,
    this.orderId,
    this.orderNumber,
    this.avatarUrl,
    this.initialMessageId,
  });

  final int peerAccountId;
  final int currentAccountId;
  final String title;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isStaff;
  final int? orderId;
  final String? orderNumber;
  final String? avatarUrl;
  final int? initialMessageId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.sentAt,
    required this.status,
    this.orderId,
  });

  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final DateTime sentAt;
  final String status;
  final int? orderId;

  factory ChatMessage.fromJson(Map<String, dynamic> row) => ChatMessage(
    id: ((row['tinnhanid'] ?? row['TinNhanID']) as num).toInt(),
    senderId: ((row['nguoiguiid'] ?? row['NguoiGuiID']) as num).toInt(),
    recipientId: ((row['nguoinhanid'] ?? row['NguoiNhanID']) as num).toInt(),
    content: (row['noidung'] ?? row['NoiDung']) as String? ?? '',
    sentAt: parseDatabaseTimestamp((row['thoigiangui'] ?? row['ThoiGianGui']) as String),
    status: (row['trangthai'] ?? row['TrangThai']) as String? ?? '',
    orderId: ((row['donhangid'] ?? row['DonHangID']) as num?)?.toInt(),
  );
}

class MessageRepository {
  static int _channelSequence = 0;
  MessageRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<int> getCurrentAccountId() async {
    final value = await _client.rpc('get_current_account_id');
    if (value is! num) throw StateError('Không tìm thấy tài khoản ứng dụng.');
    return value.toInt();
  }

  Future<int> getSupportAccountId() async {
    final value = await _client.rpc('get_support_chat_recipient');
    if (value is! num) throw StateError('Cửa hàng chưa cấu hình tài khoản hỗ trợ.');
    return value.toInt();
  }

  Future<ChatThread> getThreadForMessage(int messageId) async {
    final accountId = await getCurrentAccountId();
    final row = await _client.from('TinNhan').select(
      'TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,ThoiGianGui,TrangThai',
    ).eq('TinNhanID', messageId).maybeSingle();
    if (row == null) throw StateError('Không tìm thấy tin nhắn.');
    final message = ChatMessage.fromJson(row);
    if (message.orderId == null &&
        message.senderId != accountId &&
        message.recipientId != accountId) {
      throw StateError('Bạn không có quyền xem tin nhắn này.');
    }
    final peerId = message.senderId == accountId ? message.recipientId : message.senderId;
    return ChatThread(
      peerAccountId: peerId,
      currentAccountId: accountId,
      title: message.orderId == null ? 'Hỗ trợ cửa hàng' : 'Trao đổi về đơn hàng',
      lastMessage: message.content,
      lastMessageAt: message.sentAt,
      unreadCount: 0,
      isStaff: false,
      orderId: message.orderId,
      orderNumber: message.orderId == null ? null : '#${message.orderId}',
      initialMessageId: messageId,
    );
  }

  Future<List<ChatThread>> getThreads({required bool isStaff, int? initialOrderId}) async {
    final accountId = await getCurrentAccountId();
    if (isStaff) {
      final rows = await _client.rpc('get_staff_chat_inbox') as List<dynamic>;
      return rows.map((raw) {
        final row = raw as Map<String, dynamic>;
        final orderId = (row['order_id'] as num?)?.toInt();
        return ChatThread(
          peerAccountId: (row['customer_account_id'] as num).toInt(),
          currentAccountId: accountId,
          title: row['customer_name'] as String? ?? 'Khách hàng',
          lastMessage: row['last_message'] as String? ?? '',
          lastMessageAt: tryParseDatabaseTimestamp(row['last_message_at'] as String?),
          unreadCount: (row['unread_count'] as num? ?? 0).toInt(),
          isStaff: true,
          orderId: orderId,
          orderNumber: row['order_number'] as String?,
          avatarUrl: row['customer_avatar_url'] as String?,
        );
      }).where((thread) => initialOrderId == null || thread.orderId == initialOrderId).toList(growable: false);
    }

    final supportId = await getSupportAccountId();
    final rows = await _client
        .from('TinNhan')
        .select('TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,ThoiGianGui,TrangThai')
        .order('ThoiGianGui', ascending: true)
        .order('TinNhanID', ascending: true);
    final unreadNotifications = await _client
        .from('thongbao')
        .select('donhangid')
        .eq('loaithongbao', 'new_message')
        .eq('dadoc', false);
    final unreadByOrder = <int?, int>{};
    for (final raw in unreadNotifications as List<dynamic>) {
      final orderId = ((raw as Map<String, dynamic>)['donhangid'] as num?)
          ?.toInt();
      unreadByOrder.update(orderId, (count) => count + 1, ifAbsent: () => 1);
    }
    final groups = <int?, List<ChatMessage>>{};
    for (final raw in rows as List<dynamic>) {
      final message = ChatMessage.fromJson(raw as Map<String, dynamic>);
      groups.putIfAbsent(message.orderId, () => []).add(message);
    }
    if (initialOrderId != null) {
      groups.removeWhere((orderId, _) => orderId != initialOrderId);
      groups.putIfAbsent(initialOrderId, () => []);
    }
    if (groups.isEmpty) groups[null] = [];

    return groups.entries.map((entry) {
      final messages = entry.value;
      final last = messages.isEmpty ? null : messages.last;
      return ChatThread(
        peerAccountId: supportId,
        currentAccountId: accountId,
        title: entry.key == null ? 'Hỗ trợ cửa hàng' : 'Trao đổi về đơn hàng',
        lastMessage: last?.content ?? 'Nhắn tin với cửa hàng',
        lastMessageAt: last?.sentAt,
        unreadCount: unreadByOrder[entry.key] ?? 0,
        isStaff: false,
        orderId: entry.key,
        orderNumber: entry.key == null ? null : '#${entry.key}',
      );
    }).toList(growable: false)
      ..sort((a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
  }

  Future<List<ChatMessage>> getMessages(ChatThread thread) async {
    final rows = thread.orderId == null
        ? await _client
              .from('TinNhan')
              .select('TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,ThoiGianGui,TrangThai')
              .isFilter('DonHangID', null)
              .order('ThoiGianGui', ascending: true)
              .order('TinNhanID', ascending: true)
        : await _client
              .from('TinNhan')
              .select('TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,ThoiGianGui,TrangThai')
              .eq('DonHangID', thread.orderId!)
              .order('ThoiGianGui', ascending: true)
              .order('TinNhanID', ascending: true);
    final messages = (rows as List<dynamic>)
        .map((row) => ChatMessage.fromJson(row as Map<String, dynamic>))
        // An order is the conversation boundary. A customer's multiple
        // accounts can be linked to the same customer/order, and staff may
        // have addressed another linked account. RLS limits order rows to
        // the order owner or authorized staff. Keep participant filtering
        // only for support chats that are not tied to an order.
        .where((message) => thread.orderId != null || (thread.isStaff
            ? message.senderId == thread.peerAccountId || message.recipientId == thread.peerAccountId
            : message.senderId == thread.currentAccountId || message.recipientId == thread.currentAccountId))
        .toList();
    // Keep display order deterministic even if the API or a cached response
    // returns rows in a different order. IDs break ties for same-time messages.
    messages.sort((a, b) {
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return messages;
  }

  Future<void> sendMessage(ChatThread thread, String content) async {
    await _client.rpc('send_chat_message', params: {
      'p_recipient_account_id': thread.peerAccountId,
      'p_content': content,
      'p_order_id': thread.orderId,
    });
  }

  Future<void> markRead(ChatThread thread) async {
    await _client.rpc('mark_chat_thread_read', params: {
      'p_peer_account_id': thread.peerAccountId,
      'p_order_id': thread.orderId,
    });
  }

  RealtimeChannel subscribe(void Function() onChange) => _client
      .channel('messages:${_client.auth.currentUser?.id ?? 'anonymous'}:${_channelSequence++}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'TinNhan',
        callback: (_) => onChange(),
      )
      .subscribe();
}
