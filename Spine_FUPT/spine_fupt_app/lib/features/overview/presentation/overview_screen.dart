import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';
import 'package:intl/intl.dart';

class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  bool _refreshing = false;

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.refresh(overviewProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('已刷新'), duration: Duration(seconds: 1)));
      }
    } catch (_) {
      // error state will be shown by the provider's .when()
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(overviewProvider);
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('你好, ${auth.user?.displayName ?? ""}'),
        actions: [
          // Notification bell with feed
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/doctor/notifications'),
          ),
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _doRefresh,
                ),
        ],
      ),
      body: overview.when(
        loading: () => const ShimmerOverview(),
        error: (e, _) => Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(ApiClient.friendlyError(e), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            _refreshing
                ? const CircularProgressIndicator()
                : FilledButton(onPressed: _doRefresh, child: const Text('重试')),
          ],
        )),
        data: (data) {
          final stats = data['stats'] as Map<String, dynamic>? ?? {};
          final totalPatients = stats['patient_total'] ?? 0;
          final pendingReviews = stats['pending_reviews'] ?? 0;
          final unreadMessages = stats['unread_messages'] ?? 0;
          final todaySchedules = stats['today_schedules'] ?? 0;
          final alertCount = stats['alerts'] ?? 0;
          final feed = data['feed'] as List? ?? [];
          final schedules = data['schedules'] as List? ?? [];

          return RefreshIndicator(
            onRefresh: _doRefresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats cards
                Row(
                  children: [
                    _StatCard(label: '患者', value: '$totalPatients', icon: Icons.people, color: theme.colorScheme.primary, onTap: () => context.go('/doctor/patients')),
                    const SizedBox(width: 12),
                    _StatCard(label: '待复核', value: '$pendingReviews', icon: Icons.biotech, color: AppColors.warning, onTap: () => context.go('/doctor/reviews')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatCard(label: '未读消息', value: '$unreadMessages', icon: Icons.chat, color: AppColors.primary, onTap: () => context.go('/doctor/chat')),
                    const SizedBox(width: 12),
                    _StatCard(label: '今日日程', value: '$todaySchedules', icon: Icons.calendar_today, color: AppColors.success),
                  ],
                ),

                // Alerts
                if (alertCount is int && alertCount > 0) ...[
                  const SizedBox(height: 24),
                  Text('警报', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(Icons.warning, color: theme.colorScheme.error),
                      title: Text('Cobb角异常警报'),
                      subtitle: Text('$alertCount 例重度或高角度病例'),
                    ),
                  ),
                ],

                // Feed
                const SizedBox(height: 24),
                Text('最近动态', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (feed.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('暂无动态'))))
                else
                  ...feed.take(10).map((f) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (f['level'] == 'warn' ? AppColors.warning : theme.colorScheme.primaryContainer),
                        child: Icon(
                          f['level'] == 'warn' ? Icons.warning : Icons.info_outline,
                          size: 18,
                          color: f['level'] == 'warn' ? Colors.white : theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(f['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(f['message']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Text(_formatTime(f['created_at']?.toString()), style: theme.textTheme.bodySmall),
                    ),
                  )),

                // Upcoming schedules
                if (schedules.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('待办日程', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...schedules.map((s) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(s['title']?.toString() ?? ''),
                      subtitle: Text(s['note']?.toString() ?? ''),
                      trailing: Text(_formatTime(s['scheduled_at']?.toString())),
                    ),
                  )),
                ],

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat.Hm().format(dt);
      }
      return DateFormat('MM-dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
