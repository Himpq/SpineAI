import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';
import '../../models.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final int conversationId;
  final String? conversationName;
  const ChatRoomScreen({super.key, required this.conversationId, this.conversationName});
  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<MessageModel> _messages = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreHistory = true;
  String? _error;
  String _channel = '';
  Timer? _readTimer;

  @override
  void initState() {
    super.initState();
    _channel = 'chat:${widget.conversationId}';
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 50 && _hasMoreHistory && !_loadingMore) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMore || !_hasMoreHistory || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final oldestId = _messages.first.id;
      final data = await ref.read(chatRepoProvider).getMessages(widget.conversationId, beforeId: oldestId);
      final rawMsgs = (data['items'] as List?) ?? [];
      final olderMsgs = rawMsgs.map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) {
        final prevExtent = _scrollCtrl.position.maxScrollExtent;
        setState(() {
          _messages.insertAll(0, olderMsgs);
          _hasMoreHistory = (data['has_more'] as bool?) ?? false;
          _loadingMore = false;
        });
        // Keep scroll position stable after inserting above
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            final diff = _scrollCtrl.position.maxScrollExtent - prevExtent;
            _scrollCtrl.jumpTo(_scrollCtrl.offset + diff);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(chatRepoProvider).getMessages(widget.conversationId);
      final rawMsgs = (data['items'] as List?) ?? (data['messages'] as List?) ?? [];
      final msgs = rawMsgs.map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
          _hasMoreHistory = (data['has_more'] as bool?) ?? false;
        });
        _scrollToBottom();
        // Subscribe to WS channel
        final ws = ref.read(wsClientProvider);
        ws.subscribe(_channel);
        ws.on('chat_message', _onWsMessage);
        // Mark read after 320ms
        _readTimer = Timer(const Duration(milliseconds: 320), _markRead);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  void _onWsMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final convId = payload['conversation_id'] as int?;
    if (convId != widget.conversationId) return;
    final msgData = payload['message'] as Map<String, dynamic>? ?? payload;
    final newMsg = MessageModel.fromJson(msgData);
    // Avoid duplicate from optimistic insert
    setState(() {
      _messages.removeWhere((m) => m.id < 0 && m.content == newMsg.content);
      _messages.add(newMsg);
    });
    _scrollToBottom();
    // Auto mark read
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 320), _markRead);
  }

  void _markRead() {
    ref.read(chatRepoProvider).markRead(widget.conversationId).then((_) {
      ref.invalidate(conversationListProvider);
      ref.invalidate(overviewProvider);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    final ws = ref.read(wsClientProvider);
    ws.off('chat_message', _onWsMessage);
    ws.unsubscribe(_channel);
    _readTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final myUserId = auth.user?.id;
    final wsConnected = ref.watch(wsConnectedProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.conversationName ?? '会话#${widget.conversationId}')),
      body: Column(
        children: [
          if (!wsConnected)
            Container(
              width: double.infinity,
              color: AppColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                  const Text('连接中断，正在重试...', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ],
                      ))
                    : _messages.isEmpty
                    ? const Center(child: Text('暂无消息'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_hasMoreHistory ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_hasMoreHistory && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Center(child: _loadingMore
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : TextButton(onPressed: _loadMoreHistory, child: const Text('加载更早的消息'))),
                            );
                          }
                          final msgIdx = _hasMoreHistory ? i - 1 : i;
                          final msg = _messages[msgIdx];
                          final isMe = msg.senderUserId == myUserId;
                          return _MessageBubble(message: msg, isMe: isMe);
                        },
                      ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: SafeArea(
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final auth = ref.read(authProvider);
    _msgCtrl.clear();
    // Optimistic local insert
    final tempMsg = MessageModel(
      id: -DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversationId,
      senderKind: 'user',
      senderUserId: auth.user?.id,
      senderName: auth.user?.displayName ?? '',
      messageType: 'text',
      content: text,
      createdAt: DateTime.now().toIso8601String(),
    );
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();
    try {
      await ref.read(chatRepoProvider).sendMessage(widget.conversationId, content: text);
    } catch (e) {
      // Remove optimistic message on failure
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == tempMsg.id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: ${ApiClient.friendlyError(e)}')));
      }
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              child: Text(message.senderName.isNotEmpty ? message.senderName[0] : '?'),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(message.senderName, style: theme.textTheme.bodySmall),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isMe ? 12 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 12),
                    ),
                  ),
                  child: _buildContent(context, theme),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  static String _formatTime(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.length >= 16 ? ts.substring(11, 16) : ts;
    }
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    final textColor = isMe ? Colors.white : theme.colorScheme.onSurface;
    switch (message.messageType) {
      case 'share_case':
        final examId = message.payload?['exam_id'];
        return GestureDetector(
          onTap: () {
            if (examId != null) {
              context.push('/doctor/reviews/$examId');
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.biotech, size: 16, color: textColor),
              const SizedBox(width: 4),
              Flexible(child: Text('[病例分享] ${message.content}', style: TextStyle(color: textColor, decoration: examId != null ? TextDecoration.underline : null))),
            ],
          ),
        );
      case 'questionnaire_share':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment, size: 16, color: textColor),
            const SizedBox(width: 4),
            Text('[问卷] ${message.content}', style: TextStyle(color: textColor)),
          ],
        );
      default:
        return Text(message.content, style: TextStyle(color: textColor));
    }
  }
}
