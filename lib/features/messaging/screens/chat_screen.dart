import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/messaging/data/message_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.thread, super.key});

  final ChatThread thread;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _repository = MessageRepository();
  final _imagePicker = ImagePicker();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _isLoadingInitial = true;
  bool _hasOlderMessages = false;
  bool _loadingOlderMessages = false;
  String? _loadError;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  bool _refreshInProgress = false;
  bool _refreshRequested = false;
  bool _sending = false;
  bool _didFocusInitialMessage = false;
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadInitialMessages();
    _channel = _repository.subscribe(_onRealtimeChange);
    // Realtime is the fast path. Periodic refresh recovers messages if the
    // socket disconnects or the platform temporarily suspends the channel.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _reloadMessages(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadMessages();
  }

  Future<void> _loadInitialMessages() async {
    try {
      final page = await _repository.getMessages(widget.thread);
      var messages = page.messages;
      var hasOlder = page.hasMore;
      final initialMessageId = widget.thread.initialMessageId;
      while (initialMessageId != null &&
          hasOlder &&
          !messages.any((message) => message.id == initialMessageId)) {
        final olderPage = await _repository.getMessages(
          widget.thread,
          before: messages.first,
        );
        messages = [...olderPage.messages, ...messages];
        hasOlder = olderPage.hasMore;
      }
      await _repository.markRead(widget.thread);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _hasOlderMessages = hasOlder;
        _isLoadingInitial = false;
        _loadError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.thread.initialMessageId != null) {
          _focusInitialMessage(_messages);
        } else {
          _scrollToBottom();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingInitial = false;
        _loadError = 'Không tải được tin nhắn. Thử lại';
      });
    }
  }

  void _onRealtimeChange() {
    if (!mounted) return;
    _reloadMessages();
  }

  void _reloadMessages() {
    if (!mounted) return;
    // Don't drop realtime events that arrive while a Supabase request is in
    // flight. Queue another read so the final insert is always fetched.
    _refreshRequested = true;
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    unawaited(_drainRefreshQueue());
  }

  Future<void> _drainRefreshQueue() async {
    try {
      while (mounted && _refreshRequested) {
        _refreshRequested = false;
        final wasAtBottom =
            _scrollController.hasClients &&
            _scrollController.position.extentAfter < 120;
        try {
          final page = await _repository.getMessages(widget.thread);
          await _repository.markRead(widget.thread);
          if (!mounted) return;
          final byId = {for (final message in _messages) message.id: message};
          for (final message in page.messages) {
            byId[message.id] = message;
          }
          setState(() {
            _messages = byId.values.toList()..sort(_compareMessages);
            _hasOlderMessages = _hasOlderMessages || page.hasMore;
            _loadError = null;
          });
          if (wasAtBottom) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
          }
        } catch (_) {
          // Realtime and periodic refresh retry transient load failures.
        }
      }
    } finally {
      _refreshInProgress = false;
      // An event can arrive between the loop condition and finally.
      if (mounted && _refreshRequested) _reloadMessages();
    }
  }

  int _compareMessages(ChatMessage a, ChatMessage b) {
    final byTime = a.sentAt.compareTo(b.sentAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasOlderMessages ||
        _loadingOlderMessages) {
      return;
    }
    if (_scrollController.position.pixels <= 100) _loadOlderMessages();
  }

  Future<void> _loadOlderMessages() async {
    if (_messages.isEmpty || !_hasOlderMessages || _loadingOlderMessages)
      return;
    setState(() => _loadingOlderMessages = true);
    final oldMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    try {
      final page = await _repository.getMessages(
        widget.thread,
        before: _messages.first,
      );
      if (!mounted) return;
      final known = _messages.map((message) => message.id).toSet();
      final older = page.messages.where((message) => known.add(message.id));
      setState(() {
        _messages = [...older, ..._messages]..sort(_compareMessages);
        _hasOlderMessages = page.hasMore;
        _loadingOlderMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - oldMaxExtent;
        _scrollController.jumpTo(oldPixels + addedExtent);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
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
    if (content.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tin nhắn tối đa 1.000 ký tự.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _repository.sendMessage(widget.thread, content);
      _textController.clear();
      if (mounted) _reloadMessages();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 80), _scrollToBottom),
      );
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

  Future<void> _sendImage() async {
    if (_sending) return;
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => _sending = true);
      final sourceBytes = await file.readAsBytes();
      if (sourceBytes.length > 25 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ảnh gốc quá lớn. Vui lòng chọn ảnh nhỏ hơn 25 MB.',
              ),
            ),
          );
        }
        return;
      }
      final jpegBytes = await FlutterImageCompress.compressWithList(
        sourceBytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 85,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
      );
      if (jpegBytes.isEmpty || jpegBytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể nén ảnh dưới 5 MB. Vui lòng chọn ảnh khác.',
              ),
            ),
          );
        }
        return;
      }
      await _repository.sendImage(widget.thread, jpegBytes, 'image/jpeg');
      if (mounted) _reloadMessages();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 80), _scrollToBottom),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không thể xử lý ảnh này. Hãy thử JPG, PNG, WebP, GIF hoặc HEIC được thiết bị hỗ trợ. ($error)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMessageActions(ChatMessage message, bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa ở phía tôi'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            if (mine && !message.recalled && message.imageUrl == null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Chỉnh sửa tin nhắn'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (mine && !message.recalled)
              ListTile(
                leading: const Icon(Icons.undo_rounded, color: Colors.red),
                title: const Text('Thu hồi với mọi người'),
                onTap: () => Navigator.pop(context, 'recall'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _editMessage(message);
      return;
    }
    if (action == 'recall') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Thu hồi tin nhắn?'),
          content: const Text(
            'Nội dung sẽ được thay bằng trạng thái đã thu hồi trong cuộc trò chuyện của mọi người.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Thu hồi'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      if (action == 'hide') {
        await _repository.hideMessage(message.id);
      } else {
        await _repository.recallMessage(message.id);
      }
      if (!mounted) return;
      if (action == 'recall') {
        setState(() {
          _messages = _messages
              .map(
                (item) => item.id == message.id
                    ? item.copyWith(content: '', recalled: true)
                    : item,
              )
              .toList();
        });
      } else {
        setState(
          () => _messages = _messages
              .where((item) => item.id != message.id)
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể thực hiện thao tác: $error')),
        );
      }
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.content);
    try {
      final content = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chỉnh sửa tin nhắn'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Nhập nội dung tin nhắn',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Lưu'),
            ),
          ],
        ),
      );
      if (content == null || !mounted) return;
      if (content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tin nhắn không được để trống.')),
        );
        return;
      }
      await _repository.editMessage(message.id, content);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map(
              (item) => item.id == message.id
                  ? item.copyWith(content: content, edited: true)
                  : item,
            )
            .toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chỉnh sửa tin nhắn: $error')),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  void _showFullImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.thread.title),
          if (widget.thread.orderNumber != null)
            Text(
              widget.thread.orderNumber!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: _isLoadingInitial
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(
                  child: TextButton(
                    onPressed: _loadInitialMessages,
                    child: Text(_loadError!),
                  ),
                )
              : _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('Bắt đầu cuộc trò chuyện với cửa hàng.'),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is OverscrollNotification &&
                        notification.metrics.pixels <=
                            notification.metrics.minScrollExtent + 1 &&
                        notification.overscroll < 0) {
                      _loadOlderMessages();
                    }
                    return false;
                  },
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    children: [
                      if (_hasOlderMessages || _loadingOlderMessages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Center(
                            child: _loadingOlderMessages
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Kéo xuống để tải tin nhắn cũ hơn',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                          ),
                        ),
                      ..._messages.map((message) {
                        final mine =
                            message.senderId == widget.thread.currentAccountId;
                        final time = message.sentAt.toLocal();
                        return Align(
                          key: _messageKeys.putIfAbsent(
                            message.id,
                            GlobalKey.new,
                          ),
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () =>
                                _showMessageActions(message, mine),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .78,
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: message.recalled
                                    ? Colors.white
                                    : message.id ==
                                          widget.thread.initialMessageId
                                    ? AppColors.primaryLight
                                    : mine
                                    ? AppColors.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: mine && !message.recalled
                                    ? null
                                    : Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (message.recalled)
                                    const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Tin nhắn đã thu hồi',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    )
                                  else if (message.imageUrl != null)
                                    GestureDetector(
                                      onTap: () =>
                                          _showFullImage(message.imageUrl!),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          message.imageUrl!,
                                          width: 220,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox(
                                                width: 220,
                                                height: 80,
                                                child: Center(
                                                  child: Text(
                                                    'Không tải được ảnh',
                                                  ),
                                                ),
                                              ),
                                        ),
                                      ),
                                    )
                                  else
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        message.content,
                                        style: TextStyle(
                                          color:
                                              mine &&
                                                  message.id !=
                                                      widget
                                                          .thread
                                                          .initialMessageId
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  if (message.edited && !message.recalled)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Tin nhắn đã chỉnh sửa',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                            color: mine
                                                ? Colors.white70
                                                : AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine && !message.recalled
                                          ? Colors.white70
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _sending ? null : _sendImage,
                  tooltip: 'Gửi ảnh',
                  icon: const Icon(Icons.image_outlined),
                ),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  tooltip: 'Gửi tin nhắn',
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  void _focusInitialMessage(List<ChatMessage> messages) {
    final messageId = widget.thread.initialMessageId;
    if (!mounted || messageId == null || _didFocusInitialMessage) return;
    ChatMessage? message;
    for (final item in messages) {
      if (item.id == messageId) {
        message = item;
        break;
      }
    }
    final key = _messageKeys[messageId];
    if (message == null || key?.currentContext == null) return;
    _didFocusInitialMessage = true;
    Scrollable.ensureVisible(
      key!.currentContext!,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
}
