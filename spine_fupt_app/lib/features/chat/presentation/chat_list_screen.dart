import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';
import '../../models.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            ref.invalidate(conversationListProvider);
            ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新')));
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: conversations.when(
        loading: () => const ShimmerChatList(),
        error: (e, _) => Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text('加载失败: ${ApiClient.friendlyError(e)}'), const SizedBox(height: 8), FilledButton(onPressed: () => ref.invalidate(conversationListProvider), child: const Text('重试'))],
        )),
        data: (list) {
          if (list.isEmpty) {
            return Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_outlined, size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                const Text('暂无聊天'),
              ],
            ));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(conversationListProvider);
              await ref.read(conversationListProvider.future);
              if (context.mounted) {
                ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新')));
              }
            },
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => _ConversationTile(conv: list[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showNewChatDialog(BuildContext context, WidgetRef ref) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> users = [];
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建聊天'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索用户...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
                        setDialogState(() => loading = true);
                        try {
                          users = await ref.read(chatRepoProvider).getChatUsers(query: searchCtrl.text);
                        } catch (_) {}
                        setDialogState(() => loading = false);
                      },
                    ),
                  ),
                  onSubmitted: (_) async {
                    setDialogState(() => loading = true);
                    try {
                      users = await ref.read(chatRepoProvider).getChatUsers(query: searchCtrl.text);
                    } catch (_) {}
                    setDialogState(() => loading = false);
                  },
                ),
                const SizedBox(height: 12),
                if (loading) const CircularProgressIndicator(),
                if (!loading && users.isNotEmpty)
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text((u['display_name'] ?? u['username'] ?? '?')[0])),
                          title: Text(u['display_name'] ?? u['username'] ?? ''),
                          subtitle: Text(u['role'] ?? ''),
                          onTap: () async {
                            Navigator.pop(ctx);
                            try {
                              final conv = await ref.read(chatRepoProvider).createConversation(type: 'private', targetUserId: u['id'] as int);
                              final id = conv.id;
                              if (id != null && context.mounted) {
                                final displayName = u['display_name'] ?? u['username'] ?? '';
                                context.push('/doctor/chat/$id?name=${Uri.encodeComponent(displayName)}');
                                ref.invalidate(conversationListProvider);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: ${ApiClient.friendlyError(e)}')));
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
        ),
      ),
    );
    searchCtrl.dispose();
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conv;
  const _ConversationTile({required this.conv});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastMsg = conv.lastMessage;
    String subtitle = '';
    if (lastMsg != null) {
      subtitle = lastMsg['content'] as String? ?? '';
      if (subtitle.length > 30) subtitle = '${subtitle.substring(0, 30)}...';
    }

    IconData typeIcon;
    switch (conv.type) {
      case 'group':
        typeIcon = Icons.group;
        break;
      case 'patient':
        typeIcon = Icons.personal_injury;
        break;
      default:
        typeIcon = Icons.person;
    }

    return ListTile(
      leading: CircleAvatar(child: Icon(typeIcon)),
      title: Text(conv.name ?? '会话#${conv.id}'),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(conv.updatedAt),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
          if (conv.unread > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('${conv.unread}', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ],
      ),
      onTap: () => context.push('/doctor/chat/${conv.id}?name=${Uri.encodeComponent(conv.name ?? '会话#${conv.id}')}'),
    );
  }

  String _formatTime(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return ts.length > 10 ? ts.substring(5, 10) : ts;
    }
  }
}
