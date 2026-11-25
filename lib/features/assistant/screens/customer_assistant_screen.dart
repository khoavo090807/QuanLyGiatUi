import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/assistant/data/customer_assistant_repository.dart';

class CustomerAssistantScreen extends StatefulWidget {
  const CustomerAssistantScreen({super.key});

  @override
  State<CustomerAssistantScreen> createState() =>
      _CustomerAssistantScreenState();
}

class _CustomerAssistantScreenState extends State<CustomerAssistantScreen> {
  final _repository = CustomerAssistantRepository();
  final _conversation = CustomerAssistantConversation.forCurrentUser();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<CustomerAssistantMessage> get _messages => _conversation.messages;
  bool get _sending => _conversation.isSending;

  @override
  void initState() {
    super.initState();
    _conversation.addListener(_onConversationChanged);
    _scrollToLatest();
  }

  @override
  void dispose() {
    _conversation.removeListener(_onConversationChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onConversationChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToLatest();
  }

  Future<void> _send([String? suggestedMessage]) async {
    final text = (suggestedMessage ?? _inputController.text).trim();
    if (text.isEmpty || _sending) return;
    _inputController.clear();
    _conversation.addMessage(
      CustomerAssistantMessage(role: 'user', content: text),
    );
    _conversation.setSending(true);

    try {
      final history = _messages.length <= 12
          ? List<CustomerAssistantMessage>.of(_messages)
          : _messages.sublist(_messages.length - 12);
      final answer = await _repository.reply(history);
      _conversation.addMessage(
        CustomerAssistantMessage(role: 'assistant', content: answer),
      );
    } catch (_) {
      _conversation.addMessage(
        const CustomerAssistantMessage(
          role: 'assistant',
          content:
              'Tôi chưa kết nối được dữ liệu lúc này. Bạn có thể thử lại hoặc nhắn cửa hàng hỗ trợ.',
        ),
      );
    } finally {
      _conversation.setSending(false);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trợ lý AI'),
        actions: [
          IconButton(
            tooltip: 'Nhắn cửa hàng hỗ trợ',
            onPressed: () => context.pushNamed(AppRoutes.messages),
            icon: const Icon(Icons.support_agent_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_sending && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final message = _messages[index];
                final isUser = message.role == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isUser
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_messages.length == 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  _SuggestionChip(
                    label: 'Đơn hàng của tôi',
                    onTap: () => _send('Tình trạng đơn hàng gần đây của tôi thế nào?'),
                  ),
                  _SuggestionChip(
                    label: 'Booking của tôi',
                    onTap: () => _send('Booking sắp tới của tôi là khi nào?'),
                  ),
                  _SuggestionChip(
                    label: 'Bảng giá',
                    onTap: () => _send('Cho tôi xem bảng giá dịch vụ hiện tại.'),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Hỏi về đơn hàng, booking, dịch vụ...',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Gửi tin nhắn',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ActionChip(label: Text(label), onPressed: onTap),
  );
}
