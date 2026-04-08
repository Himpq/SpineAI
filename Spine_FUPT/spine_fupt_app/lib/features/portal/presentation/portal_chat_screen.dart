import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class PortalChatScreen extends ConsumerStatefulWidget {
  const PortalChatScreen({super.key});
  @override
  ConsumerState<PortalChatScreen> createState() => _PortalChatScreenState();
}

class _PortalChatScreenState extends ConsumerState<PortalChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(authProvider).portalToken;
    if (token == null) return;
    try {
      final data = await ref.read(portalRepoProvider).getPortalChat(token);
      if (mounted) {
        setState(() {
          _messages = (data['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loading = false;
        });
        _scrollToBottom();
        // Subscribe to chat channel if available
        final conv = data['conversation'] as Map<String, dynamic>?;
        final convId = conv?['id'] ?? data['conversation_id'];
        if (convId != null) {
          _channel = 'chat:$convId';
          final ws = ref.read(wsClientProvider);
          ws.subscribe(_channel!);
          ws.on('chat_message', _onWsMessage);
        }
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  void _onWsMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final msg = payload['message'] as Map<String, dynamic>? ?? payload;
    final msgId = msg['id'];
    setState(() {
      // Remove optimistic placeholder if exists
      _messages.removeWhere((m) => (m['id'] as int?) != null && (m['id'] as int) < 0 && m['content'] == msg['content']);
      // Dedup by id
      if (msgId != null && _messages.any((m) => m['id'] == msgId)) return;
      _messages.add(msg);
    });
    _scrollToBottom();
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
    if (_channel != null) {
      final ws = ref.read(wsClientProvider);
      ws.off('chat_message', _onWsMessage);
      ws.unsubscribe(_channel!);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('联系医生')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('加载失败: $_error'),
                          const SizedBox(height: 8),
                          FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('重试')),
                        ],
                      ))
                : _messages.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_outlined, size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('暂无消息，发送第一条消息吧'),
                        ],
                      ))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isPatient = msg['sender_kind'] == 'patient';
                          return _PortalBubble(msg: msg, isMe: isPatient);
                        },
                      ),
          ),
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
                  onPressed: _sending ? null : _send,
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
    final token = ref.read(authProvider).portalToken;
    if (token == null) return;

    _msgCtrl.clear();
    // Optimistic local insert
    final auth = ref.read(authProvider);
    final tempMsg = <String, dynamic>{
      'id': -DateTime.now().millisecondsSinceEpoch,
      'sender_kind': 'patient',
      'sender_name': auth.portalData?['patient']?['name'] ?? '我',
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _messages.add(tempMsg);
      _sending = true;
    });
    _scrollToBottom();
    try {
      await ref.read(portalRepoProvider).sendMessage(token, text);
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempMsg['id']));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: ${ApiClient.friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _PortalBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  const _PortalBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = msg['content'] as String? ?? '';
    final name = msg['sender_name'] as String? ?? '';
    final time = msg['created_at'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(radius: 16, child: Text(name.isNotEmpty ? name[0] : '医')),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe) Text(name, style: theme.textTheme.bodySmall),
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
                  child: Text(content, style: TextStyle(color: isMe ? Colors.white : theme.colorScheme.onSurface)),
                ),
                if (time != null)
                  Text(_formatTime(time),
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
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
}
