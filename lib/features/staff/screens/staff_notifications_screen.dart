import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_notification_repository.dart';

class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({
    required this.unreadNotificationCount,
    super.key,
  });

  final ValueNotifier<int> unreadNotificationCount;

  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  final _repository = StaffNotificationRepository();
  final _scrollController = ScrollController();
  final _selectedIds = <int>{};
  List<StaffNotification> _notifications = const [];
  int _page = 1;
  int _lastPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isBusy = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadFirstPage());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadFirstPage(),
    );
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _repository.getPage();
      if (!mounted) return;
      setState(() {
        _notifications = page.notifications;
        _page = page.page;
        _lastPage = page.lastPage;
        _selectedIds.retainAll(_notifications.map((item) => item.id));
        _isLoading = false;
      });
      widget.unreadNotificationCount.value = page.unreadCount;
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || _page >= _lastPage) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _repository.getPage(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _notifications = [..._notifications, ...page.notifications];
        _page = page.page;
        _lastPage = page.lastPage;
        _isLoadingMore = false;
      });
      widget.unreadNotificationCount.value = page.unreadCount;
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        _showError('Không thể tải thêm thông báo.');
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
      await _loadFirstPage();
    } catch (_) {
      if (mounted) _showError('Không thể cập nhật thông báo.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _markAllRead() => _runAction(_repository.markAllRead);

  Future<void> _markSelected(bool read) async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList(growable: false);
    setState(_selectedIds.clear);
    await _runAction(() => _repository.markManyRead(ids, read: read));
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty || !await _confirmDelete(_selectedIds.length)) {
      return;
    }
    if (!mounted) return;
    final ids = _selectedIds.toList(growable: false);
    setState(_selectedIds.clear);
    await _runAction(() => _repository.deleteMany(ids));
  }

  Future<void> _handleItemAction(
    StaffNotification notification,
    String action,
  ) async {
    if (action == 'delete') {
      if (!await _confirmDelete(1)) return;
      await _runAction(() => _repository.delete(notification.id));
    } else {
      await _runAction(
        () => _repository.markRead(notification.id, read: action == 'read'),
      );
    }
  }

  Future<void> _open(StaffNotification notification) async {
    if (!notification.isRead) {
      try {
        await _repository.markRead(notification.id, read: true);
        widget.unreadNotificationCount.value =
            (widget.unreadNotificationCount.value - 1)
                .clamp(0, 1 << 30)
                .toInt();
      } catch (_) {
        if (mounted) _showError('Không thể cập nhật thông báo.');
        return;
      }
    }
    if (mounted) Navigator.pop(context, notification);
  }

  Future<bool> _confirmDelete(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xóa thông báo?'),
          content: Text(
            count == 1
                ? 'Thông báo này sẽ bị xóa.'
                : 'Xóa $count thông báo đã chọn?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa'),
            ),
          ],
        ),
      ) ??
      false;

  void _toggleSelection(int id, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == _notifications.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_notifications.map((item) => item.id));
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _timeLabel(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'Vừa xong';
    if (difference.inHours < 1) return '${difference.inMinutes} phút trước';
    if (difference.inDays < 1) return '${difference.inHours} giờ trước';
    if (difference.inDays < 7) return '${difference.inDays} ngày trước';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thông báo'),
      actions: [
        IconButton(
          tooltip: 'Chọn tất cả',
          onPressed: _isBusy || _notifications.isEmpty ? null : _toggleAll,
          icon: Icon(
            _selectedIds.length == _notifications.length &&
                    _notifications.isNotEmpty
                ? Icons.check_box
                : Icons.check_box_outline_blank,
          ),
        ),
        IconButton(
          tooltip: 'Đánh dấu đã đọc',
          onPressed: _isBusy || _selectedIds.isEmpty
              ? null
              : () => _markSelected(true),
          icon: const Icon(Icons.mark_email_read_outlined),
        ),
        IconButton(
          tooltip: 'Đánh dấu chưa đọc',
          onPressed: _isBusy || _selectedIds.isEmpty
              ? null
              : () => _markSelected(false),
          icon: const Icon(Icons.mark_email_unread_outlined),
        ),
        IconButton(
          tooltip: 'Xóa đã chọn',
          onPressed: _isBusy || _selectedIds.isEmpty ? null : _deleteSelected,
          icon: const Icon(Icons.delete_outline),
        ),
        IconButton(
          tooltip: 'Đánh dấu tất cả đã đọc',
          onPressed: _isBusy ? null : _markAllRead,
          icon: _isBusy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.done_all),
        ),
      ],
    ),
    body: _error != null && _notifications.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 8),
                const Text('Không tải được thông báo.'),
                TextButton(
                  onPressed: _loadFirstPage,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          )
        : _isLoading && _notifications.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadFirstPage,
            child: _notifications.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('Bạn chưa có thông báo nào.')),
                    ],
                  )
                : ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == _notifications.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final notification = _notifications[index];
                      final selected = _selectedIds.contains(notification.id);
                      return Card(
                        elevation: 0,
                        color: selected
                            ? AppColors.primaryLight
                            : notification.isRead
                            ? AppColors.surface
                            : AppColors.primaryExtraLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppColors.divider),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: notification.isRead
                                ? AppColors.border
                                : AppColors.primary,
                            foregroundColor: Colors.white,
                            child: const Icon(Icons.notifications_outlined),
                          ),
                          title: Text(
                            notification.title,
                            style: AppTypography.title.copyWith(
                              fontWeight: notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notification.message),
                                const SizedBox(height: 6),
                                Text(
                                  _timeLabel(notification.sentAt),
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                enabled: !_isBusy,
                                onSelected: (action) =>
                                    _handleItemAction(notification, action),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: notification.isRead
                                        ? 'unread'
                                        : 'read',
                                    child: Text(
                                      notification.isRead
                                          ? 'Đánh dấu chưa đọc'
                                          : 'Đánh dấu đã đọc',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xóa thông báo'),
                                  ),
                                ],
                              ),
                              Checkbox(
                                value: selected,
                                onChanged: _isBusy
                                    ? null
                                    : (value) => _toggleSelection(
                                        notification.id,
                                        value,
                                      ),
                              ),
                            ],
                          ),
                          onTap: () => _selectedIds.isNotEmpty
                              ? _toggleSelection(notification.id, !selected)
                              : _open(notification),
                        ),
                      );
                    },
                  ),
          ),
  );
}
