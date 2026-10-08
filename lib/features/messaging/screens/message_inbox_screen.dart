import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';
import 'package:app_quanly_giaiui/features/messaging/data/message_repository.dart';

class MessageInboxScreen extends StatefulWidget {
  const MessageInboxScreen({this.initialOrderId, super.key});

  final int? initialOrderId;

  @override
  State<MessageInboxScreen> createState() => _MessageInboxScreenState();
}

class _MessageInboxScreenState extends State<MessageInboxScreen> {
  final _repository = MessageRepository();
  late Future<List<ChatThread>> _threadsFuture;
  bool? _isStaff;
  RealtimeChannel? _channel;
  bool _autoOpenedInitialOrder = false;

  @override
  void initState() {
    super.initState();
    _threadsFuture = _loadThreads();
    _channel = _repository.subscribe(_refreshSilently);
  }

  Future<List<ChatThread>> _loadThreads() async {
    final roles = await AuthRepository().getCurrentRoles();
    final isStaff = roles.any((role) => role == 'Nhân viên' || role == 'Chủ cửa hàng' || role.startsWith('Quản lý'));
    _isStaff = isStaff;
    return _repository.getThreads(isStaff: isStaff, initialOrderId: widget.initialOrderId);
  }

  void _refreshSilently() {
    if (!mounted || _isStaff == null) return;
    final future = _repository.getThreads(
      isStaff: _isStaff!, initialOrderId: widget.initialOrderId,
    );
    setState(() {
      _threadsFuture = future;
    });
  }

  Future<void> _refresh() async {
    final future = _loadThreads();
    setState(() {
      _threadsFuture = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder shows the retry state.
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  String _time(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final today = DateTime.now();
    if (local.year == today.year && local.month == today.month && local.day == today.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isStaff == true ? 'Tin nhắn khách hàng' : 'Tin nhắn')),
    body: FutureBuilder<List<ChatThread>>(
      future: _threadsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: AppColors.textMuted),
              const SizedBox(height: 12),
              const Text('Không tải được hộp thư.'),
              TextButton(onPressed: _refresh, child: const Text('Thử lại')),
            ]),
          ));
        }
        final threads = snapshot.data ?? const <ChatThread>[];
        if (widget.initialOrderId != null && threads.length == 1 && !_autoOpenedInitialOrder) {
          _autoOpenedInitialOrder = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.pushReplacementNamed(AppRoutes.chat, extra: threads.single);
          });
          return const Center(child: CircularProgressIndicator());
        }
        if (threads.isEmpty) {
          return const Center(child: Text('Chưa có tin nhắn nào.'));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              final thread = threads[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: thread.avatarUrl == null ? null : NetworkImage(thread.avatarUrl!),
                  child: thread.avatarUrl == null
                      ? Icon(thread.isStaff ? Icons.person_outline : Icons.storefront_outlined, color: AppColors.primary)
                      : null,
                ),
                title: Row(children: [
                  Expanded(child: Text(thread.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (thread.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: Text('${thread.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                ]),
                subtitle: Text(
                  '${thread.orderNumber == null ? '' : '${thread.orderNumber} · '}${thread.lastMessage}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_time(thread.lastMessageAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                onTap: () => context.pushNamed(AppRoutes.chat, extra: thread).then((_) => _refreshSilently()),
              );
            },
          ),
        );
      },
    ),
  );
}
