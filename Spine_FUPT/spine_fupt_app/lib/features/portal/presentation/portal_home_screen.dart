import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class PortalHomeScreen extends ConsumerWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final portalData = auth.portalData;
    final theme = Theme.of(context);

    if (portalData == null) {
      return const Scaffold(body: Center(child: Text('无数据')));
    }

    final patient = portalData['patient'] as Map<String, dynamic>? ?? {};
    final exams = (portalData['uploads'] as List?)?.cast<Map<String, dynamic>>() ?? (portalData['exams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final latestExam = exams.isNotEmpty ? exams.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的健康'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出',
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (auth.portalToken != null) {
            await ref.read(authProvider.notifier).enterPortal(auth.portalToken!);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Patient info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      child: Text((patient['name'] ?? '?')[0], style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient['name'] ?? '', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (patient['sex'] != null) Text('${patient['sex']}  ', style: theme.textTheme.bodyMedium),
                          if (patient['age'] != null) Text('${patient['age']}岁', style: theme.textTheme.bodyMedium),
                        ]),
                      ],
                    )),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quick actions
            Row(
              children: [
                _QuickAction(icon: Icons.timeline, label: '随访记录', onTap: () => context.go('/portal/timeline')),
                const SizedBox(width: 12),
                _QuickAction(icon: Icons.upload, label: '上传影像', onTap: () => context.go('/portal/upload')),
                const SizedBox(width: 12),
                _QuickAction(icon: Icons.chat, label: '联系医生', onTap: () => context.go('/portal/chat')),
              ],
            ),

            const SizedBox(height: 12),

            // Spine screening entry
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push('/portal/screening'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.health_and_safety, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('脊柱健康筛查', style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('问卷自评 · 体测引导 · 风险提示', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    )),
                    const Icon(Icons.chevron_right, color: Colors.white70),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Latest exam result
            if (latestExam != null) ...[
              Text('最新检查', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _ExamSummaryCard(exam: latestExam, baseUrl: ref.read(serverUrlProvider)),
            ] else ...[
              Center(child: Column(
                children: [
                  Icon(Icons.medical_information_outlined, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('暂无检查记录'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('/portal/upload'),
                    icon: const Icon(Icons.upload),
                    label: const Text('上传影像'),
                  ),
                ],
              )),
            ],

            // Show exam count
            if (exams.length > 1) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/portal/timeline'),
                child: Text('查看全部 ${exams.length} 条记录 →'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出患者门户'),
        content: const Text('确定要退出吗？退出后需要重新使用链接或二维码登录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(authProvider.notifier).leavePortal();
      } catch (_) {}
      // Router redirect will auto-navigate to /login
    }
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamSummaryCard extends StatelessWidget {
  final Map<String, dynamic> exam;
  final String baseUrl;
  const _ExamSummaryCard({required this.exam, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cobbAngle = (exam['cobb_angle'] as num?)?.toDouble();
    final severity = exam['severity_label'] as String?;
    final spineClass = exam['spine_class_text'] as String?;
    final imageUrl = exam['image_url'] as String?;
    final createdAt = exam['upload_date'] as String? ?? exam['created_at'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white54),
                      ),
                    )
                  : const Icon(Icons.image, color: Colors.white54),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (spineClass != null) Text(spineClass, style: theme.textTheme.titleSmall),
                if (cobbAngle != null) Text('Cobb角: ${cobbAngle.toStringAsFixed(1)}°', style: theme.textTheme.bodyMedium),
                if (severity != null) Text('严重程度: $severity', style: theme.textTheme.bodySmall),
                if (createdAt != null) Text(createdAt.substring(0, 10), style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
              ],
            )),
          ],
        ),
      ),
    );
  }
}
