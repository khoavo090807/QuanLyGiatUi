import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/utils/database_timestamp.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';

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
    this.imageUrl,
    this.edited = false,
    this.recalled = false,
  });

  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final DateTime sentAt;
  final String status;
  final int? orderId;
  final String? imageUrl;
  final bool edited;
  final bool recalled;

  ChatMessage copyWith({String? content, bool? edited, bool? recalled}) =>
      ChatMessage(
        id: id,
        senderId: senderId,
        recipientId: recipientId,
        content: content ?? this.content,
        sentAt: sentAt,
        status: status,
        orderId: orderId,
        imageUrl: imageUrl,
        edited: edited ?? this.edited,
        recalled: recalled ?? this.recalled,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> row) => ChatMessage(
    id: ((row['tinnhanid'] ?? row['TinNhanID']) as num).toInt(),
    senderId: ((row['nguoiguiid'] ?? row['NguoiGuiID']) as num).toInt(),
    recipientId: ((row['nguoinhanid'] ?? row['NguoiNhanID']) as num).toInt(),
    content: (row['noidung'] ?? row['NoiDung']) as String? ?? '',
    sentAt: parseDatabaseTimestamp(
      (row['thoigiangui'] ?? row['ThoiGianGui']) as String,
    ),
    status: (row['trangthai'] ?? row['TrangThai']) as String? ?? '',
    orderId: ((row['donhangid'] ?? row['DonHangID']) as num?)?.toInt(),
    imageUrl: (row['ImageUrl'] ?? row['image_url']) as String?,
    edited: (row['DaChinhSua'] ?? row['dachinhsua']) as bool? ?? false,
    recalled:
        (row['DaThuHoi'] ?? row['dathuhoi']) as bool? ??
        (row['noidung'] ?? row['NoiDung']) == 'Tin nhắn đã thu hồi',
  );
}

class ChatThreadPage {
  const ChatThreadPage({required this.threads, required this.hasMore});

  final List<ChatThread> threads;
  final bool hasMore;
}

class ChatMessagePage {
  const ChatMessagePage({required this.messages, required this.hasMore});

  final List<ChatMessage> messages;
  final bool hasMore;
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
    if (value is! num) {
      throw StateError('Cửa hàng chưa cấu hình tài khoản hỗ trợ.');
    }
    return value.toInt();
  }

  Future<ChatThread> getSupportThread() async => ChatThread(
    peerAccountId: await getSupportAccountId(),
    currentAccountId: await getCurrentAccountId(),
    title: 'Cửa hàng hỗ trợ',
    lastMessage: '',
    lastMessageAt: null,
    unreadCount: 0,
    isStaff: false,
  );

  Future<ChatThread> getThreadForMessage(int messageId) async {
    final accountId = await getCurrentAccountId();
    final response = await _client.functions.invoke(
      'chat-encryption',
      body: {'action': 'message', 'message_id': messageId},
    );
    final row = response.data as Map<String, dynamic>;
    final message = ChatMessage.fromJson(row);
    if (message.orderId == null &&
        message.senderId != accountId &&
        message.recipientId != accountId) {
      throw StateError('Bạn không có quyền xem tin nhắn này.');
    }
    final peerId = message.senderId == accountId
        ? message.recipientId
        : message.senderId;
    return ChatThread(
      peerAccountId: peerId,
      currentAccountId: accountId,
      title: message.orderId == null
          ? 'Cửa hàng hỗ trợ'
          : 'Trao đổi về đơn hàng',
      lastMessage: message.content,
      lastMessageAt: message.sentAt,
      unreadCount: 0,
      isStaff: false,
      orderId: message.orderId,
      orderNumber: message.orderId == null
          ? null
          : FormatterUtils.formatOrderId(message.orderId!),
      initialMessageId: messageId,
    );
  }

  Future<ChatThreadPage> getThreads({
    required bool isStaff,
    int? initialOrderId,
    int page = 0,
    int pageSize = 10,
  }) async {
    final response = await _client.functions.invoke(
      'chat-encryption',
      body: {
        'action': 'threads',
        'is_staff': isStaff,
        'initial_order_id': initialOrderId,
        'page': page,
        'page_size': pageSize,
      },
    );
    final result = response.data as Map<String, dynamic>;
    final rows = result['threads'] as List<dynamic>;
    final threads = rows
        .map((raw) {
          final row = raw as Map<String, dynamic>;
          final orderId = (row['order_id'] as num?)?.toInt();
          final threadIsStaff = row['is_staff'] as bool? ?? isStaff;
          return ChatThread(
            peerAccountId: (row['peer_account_id'] as num).toInt(),
            currentAccountId: (row['current_account_id'] as num).toInt(),
            title: !threadIsStaff && orderId == null
                ? 'Cửa hàng hỗ trợ'
                : row['title'] as String? ?? 'Tin nhắn',
            lastMessage: row['last_message'] as String? ?? '',
            lastMessageAt: tryParseDatabaseTimestamp(
              row['last_message_at'] as String?,
            ),
            unreadCount: (row['unread_count'] as num? ?? 0).toInt(),
            isStaff: threadIsStaff,
            orderId: orderId,
            orderNumber: row['order_number'] is String
                ? FormatterUtils.formatOrderCode(row['order_number'] as String)
                : null,
            avatarUrl: row['avatar_url'] as String?,
          );
        })
        .toList(growable: false);
    return ChatThreadPage(
      threads: threads,
      hasMore: result['has_more'] as bool? ?? false,
    );
  }

  Future<ChatMessagePage> getMessages(
    ChatThread thread, {
    ChatMessage? before,
    int pageSize = 10,
  }) async {
    final response = await _client.functions.invoke(
      'chat-encryption',
      body: {
        'action': 'messages',
        'order_id': thread.orderId,
        'peer_account_id': thread.peerAccountId,
        'current_account_id': thread.currentAccountId,
        'is_staff': thread.isStaff,
        'page_size': pageSize,
        if (before != null) 'before_message_id': before.id,
      },
    );
    final result = response.data as Map<String, dynamic>;
    final messages = (result['messages'] as List<dynamic>)
        .map((row) => ChatMessage.fromJson(row as Map<String, dynamic>))
        .toList();
    // Keep display order deterministic even if the API or a cached response
    // returns rows in a different order. IDs break ties for same-time messages.
    messages.sort((a, b) {
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return ChatMessagePage(
      messages: messages,
      hasMore: result['has_more'] as bool? ?? false,
    );
  }

  Future<void> sendMessage(ChatThread thread, String content) async {
    await _client.functions.invoke(
      'chat-encryption',
      body: {
        'action': 'send',
        'peer_account_id': thread.peerAccountId,
        'content': content,
        'order_id': thread.orderId,
      },
    );
  }

  Future<void> sendImage(
    ChatThread thread,
    Uint8List bytes,
    String mimeType,
  ) async {
    await _client.functions.invoke(
      'chat-encryption',
      body: {
        'action': 'send_image',
        'peer_account_id': thread.peerAccountId,
        'order_id': thread.orderId,
        'mime_type': mimeType,
        'image_base64': base64Encode(bytes),
      },
    );
  }

  Future<void> editMessage(int messageId, String content) async {
    await _client.functions.invoke(
      'chat-encryption',
      body: {'action': 'edit', 'message_id': messageId, 'content': content},
    );
  }

  Future<void> hideMessage(int messageId) async {
    final hidden = await _client.rpc(
      'hide_chat_message',
      params: {'p_message_id': messageId},
    );
    if (hidden != true) throw StateError('Không thể xóa tin nhắn này.');
  }

  Future<void> recallMessage(int messageId) async {
    final response = await _client.functions.invoke(
      'chat-encryption',
      body: {'action': 'recall_message', 'message_id': messageId},
    );
    if ((response.data as Map<String, dynamic>)['ok'] != true) {
      throw StateError('Chỉ có thể thu hồi tin nhắn do bạn gửi.');
    }
  }

  Future<void> markRead(ChatThread thread) async {
    await _client.rpc(
      'mark_chat_thread_read',
      params: {
        'p_peer_account_id': thread.peerAccountId,
        'p_order_id': thread.orderId,
      },
    );
  }

  RealtimeChannel subscribe(void Function() onChange) => _client
      .channel(
        'messages:${_client.auth.currentUser?.id ?? 'anonymous'}:${_channelSequence++}',
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'TinNhan',
        callback: (_) => onChange(),
      )
      .subscribe();
}
