import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAssistantMessage {
  const CustomerAssistantMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class CustomerAssistantConversation extends ChangeNotifier {
  CustomerAssistantConversation._()
    : messages = [
        const CustomerAssistantMessage(
          role: 'assistant',
          content:
              'Xin chào! Tôi có thể hỗ trợ thông tin đơn hàng, booking, dịch vụ và bảng giá của cửa hàng.',
        ),
      ];

  static final Map<String, CustomerAssistantConversation> _sessions = {};

  factory CustomerAssistantConversation.forCurrentUser() {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return _sessions.putIfAbsent(userId, CustomerAssistantConversation._);
  }

  final List<CustomerAssistantMessage> messages;
  bool isSending = false;

  void addMessage(CustomerAssistantMessage message) {
    messages.add(message);
    notifyListeners();
  }

  void setSending(bool value) {
    isSending = value;
    notifyListeners();
  }
}

class CustomerAssistantRepository {
  CustomerAssistantRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> reply(List<CustomerAssistantMessage> messages) async {
    final response = await _client.functions.invoke(
      'customer-ai-assistant',
      body: {
        'messages': messages
            .map((message) => {
                  'role': message.role,
                  'content': message.content,
                })
            .toList(growable: false),
      },
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw StateError('Trợ lý chưa thể trả lời lúc này. Vui lòng thử lại sau.');
    }
    final answer = data['answer'];
    if (answer is! String || answer.isEmpty) {
      throw StateError('Trợ lý chưa nhận được câu trả lời hợp lệ.');
    }
    return answer;
  }
}
