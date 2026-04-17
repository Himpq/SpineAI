import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── User profile card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (user?.displayName ?? user?.username ?? '?')[0].toUpperCase(),
                      style: TextStyle(fontSize: 24, color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.displayName ?? user?.username ?? '', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          user?.role == 'admin' ? '管理员' : user?.role == 'nurse' ? '护士' : '医生',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── General settings ──
          _SectionHeader('通用'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('服务器配置'),
                  subtitle: Text(ref.watch(serverUrlProvider), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/server-config'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('主题模式'),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 18)),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (v) {
                      ref.read(themeModeProvider.notifier).state = v.first;
                      saveThemeMode(v.first);
                    },
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清除缓存'),
                  subtitle: const Text('清除图片缓存和临时数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _clearCache(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── System & diagnostics ──
          _SectionHeader('系统'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('系统状态'),
                  subtitle: const Text('数据库和推理服务器'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSystemStatus(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('操作日志'),
                  subtitle: const Text('查看系统操作记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLogs(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Admin section ──
          if (user?.isAdmin == true) ...[
            _SectionHeader('管理'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('用户管理'),
                    subtitle: const Text('查看和管理系统用户'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/doctor/users'),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.quiz_outlined),
                    title: const Text('筛查量表管理'),
                    subtitle: const Text('编辑和管理脊柱健康筛查量表'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/doctor/screening-scales'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── About ──
          _SectionHeader('关于'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.medical_services_outlined),
                  title: Text('脊柱AI影像随访平台'),
                  subtitle: Text('版本 1.0.0'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('开源许可'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: '脊柱AI影像随访平台',
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Logout ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _clearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存并重新登录吗？\n这将清除图片缓存和登录信息。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      imageCache.clear();
      imageCache.clearLiveImages();
      await ApiClient.instance.clearCookies();
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    }
  }

  void _showSystemStatus(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final status = await ref.read(overviewRepoProvider).getSystemStatus();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final db = status['database'] as Map<String, dynamic>? ?? {};
      final inf = status['inference_server'] as Map<String, dynamic>? ?? {};
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('系统状态'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusRow('数据库', db['status']?.toString() ?? 'unknown'),
                _StatusRow('患者数', db['patients']?.toString() ?? '0'),
                _StatusRow('检查数', db['exams']?.toString() ?? '0'),
                _StatusRow('消息数', db['messages']?.toString() ?? '0'),
                const Divider(),
                _StatusRow('推理服务器', inf['status']?.toString() ?? 'unknown'),
                _StatusRow('推理队列', inf['queue_length']?.toString() ?? '0'),
                _StatusRow('近期延迟', '${inf['recent_latency_ms']?.toString() ?? '-'}ms'),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取状态失败: $e')));
    }
  }

  void _showLogs(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final logs = await ref.read(overviewRepoProvider).getLogs();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('操作日志'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: logs.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final log = logs[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          log['level'] == 'warn' ? Icons.warning_amber : Icons.info_outline,
                          size: 20,
                          color: log['level'] == 'warn' ? AppColors.warning : null,
                        ),
                        title: Text(log['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(log['message']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(log['created_at']?.toString().substring(11, 16) ?? '', style: Theme.of(ctx).textTheme.bodySmall),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载日志失败: $e')));
    }
  }

}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatusRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w500))],
      ),
    );
  }
}
