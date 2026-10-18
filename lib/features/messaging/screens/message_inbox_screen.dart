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
  final _scrollController = ScrollController();
  List<ChatThread> _threads = const [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _loadError;
  int _page = 0;
  bool? _isStaff;
  RealtimeChannel? _channel;
  bool _autoOpenedInitialOrder = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
    _channel = _repository.subscribe(_refreshSilently);
  }

  String _threadKey(ChatThread thread) =>
      '${thread.peerAccountId}:${thread.orderId ?? 'support'}';

  Future<void> _loadFirstPage({bool preserveLoaded = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = !preserveLoaded;
        _loadError = null;
      });
    }
    try {
      final roles = await AuthRepository().getCurrentRoles();
      final isStaff = roles.any((role) =>
          role == 'Nhân viên' ||
          role == 'Chủ cửa hàng' ||
          role.startsWith('Quản lý'));
      _isStaff = isStaff;
      final result = await _repository.getThreads(
        isStaff: isStaff,
        initialOrderId: widget.initialOrderId,
      );
      if (!mounted) return;
      setState(() {
        if (preserveLoaded) {
          final byKey = {for (final thread in _threads) _threadKey(thread): thread};
          for (final thread in result.threads) {
            byKey[_threadKey(thread)] = thread;
          }
          _threads = byKey.values.toList()
            ..sort((a, b) =>
                (b.lastMessageAt?.compareTo(a.lastMessageAt ?? DateTime(0)) ?? 0));
          _hasMore = _hasMore || result.hasMore;
        } else {
          _threads = result.threads;
          _page = 0;
          _hasMore = result.hasMore;
        }
        _isLoading = false;
      });
      if (widget.initialOrderId != null &&
          result.threads.length == 1 &&
          !_autoOpenedInitialOrder) {
        _autoOpenedInitialOrder = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.pushReplacementNamed(
              AppRoutes.chat,
              extra: result.threads.single,
            );
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Không tải được hộp thư.';
      });
    }
  }

  void _refreshSilently() {
    if (!mounted) return;
    _loadFirstPage(preserveLoaded: _threads.isNotEmpty);
  }

  Future<void> _refresh() async {
    await _loadFirstPage();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoadingMore) return;
    if (_scrollController.position.extentAfter < 300) {
      _loadMoreThreads();
    }
  }

  Future<void> _loadMoreThreads() async {
    if (!_hasMore || _isLoadingMore || _isStaff == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _repository.getThreads(
        isStaff: _isStaff!,
        initialOrderId: widget.initialOrderId,
        page: _page + 1,
      );
      if (!mounted) return;
      final known = _threads.map(_threadKey).toSet();
      setState(() {
        _threads = [
          ..._threads,
          ...result.threads.where((thread) => known.add(_threadKey(thread))),
        ];
        _page++;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
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
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(_loadError!),
              TextButton(onPressed: _refresh, child: const Text('Thử lại')),
            ]),
          ))
        : RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _threads.isEmpty ? 1 : _threads.length + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              if (_threads.isEmpty) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: Text('Chưa có tin nhắn nào.')),
                );
              }
              if (index >= _threads.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final thread = _threads[index];
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
        ),
  );
}
