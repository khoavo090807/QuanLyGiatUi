import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/messaging/data/message_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.thread, super.key});

  final ChatThread thread;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _repository = MessageRepository();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late Future<List<ChatMessage>> _messagesFuture;
  RealtimeChannel? _channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messagesFuture = _loadMessages();
    _channel = _repository.subscribe(_onRealtimeChange);
  }

  Future<List<ChatMessage>> _loadMessages() async {
    final rows = await _repository.getMessages(widget.thread);
    await _repository.markRead(widget.thread);
    return rows;
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    _reloadMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _reloadMessages() {
    final future = _loadMessages();
    setState(() {
      _messagesFuture = future;
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final content = _textController.text.trim();
    if (content.isEmpty || _sending) return;
    if (content.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tin nhắn tối đa 2.000 ký tự.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await _repository.sendMessage(widget.thread, content);
      _textController.clear();
      if (mounted) _reloadMessages();
      unawaited(Future<void>.delayed(const Duration(milliseconds: 80), _scrollToBottom));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không gửi được tin nhắn: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.thread.title),
        if (widget.thread.orderNumber != null)
          Text(widget.thread.orderNumber!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    ),
    body: Column(children: [
      Expanded(
        child: FutureBuilder<List<ChatMessage>>(
          future: _messagesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: TextButton(
                onPressed: _reloadMessages,
                child: const Text('Không tải được tin nhắn. Thử lại'),
              ));
            }
            final messages = snapshot.data ?? const <ChatMessage>[];
            if (messages.isEmpty) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(28),
                child: Text('Bắt đầu cuộc trò chuyện với cửa hàng.'),
              ));
            }
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final mine = message.senderId == widget.thread.currentAccountId;
                final time = message.sentAt.toLocal();
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: mine ? null : Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(message.content, style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary)),
                        ),
                        const SizedBox(height: 4),
                        Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.textMuted)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Nhập tin nhắn...',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: 'Gửi tin nhắn',
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]),
  );
}
