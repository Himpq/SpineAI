import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class PortalTimelineScreen extends ConsumerStatefulWidget {
  const PortalTimelineScreen({super.key});
  @override
  ConsumerState<PortalTimelineScreen> createState() => _PortalTimelineScreenState();
}

class _PortalTimelineScreenState extends ConsumerState<PortalTimelineScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final portalData = auth.portalData;
    final theme = Theme.of(context);
    final baseUrl = ref.read(serverUrlProvider);

    final exams = (portalData?['uploads'] as List?)?.cast<Map<String, dynamic>>() ?? (portalData?['exams'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('随访记录')),
      body: RefreshIndicator(
        onRefresh: () async {
          final token = ref.read(authProvider).portalToken;
          if (token != null) await ref.read(authProvider.notifier).enterPortal(token);
          if (mounted) ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新')));
        },
        child: exams.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timeline, size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    const Text('暂无随访记录'),
                    const SizedBox(height: 8),
                    Text('下拉可刷新', style: theme.textTheme.bodySmall),
                  ],
                )),
              ])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: exams.length,
                itemBuilder: (_, i) => _buildTimelineItem(exams, i, theme, baseUrl),
              ),
      ),
    );
  }

  Widget _buildTimelineItem(List<Map<String, dynamic>> exams, int i, ThemeData theme, String baseUrl) {
    final exam = exams[i];
    final spineClass = exam['spine_class'] as String?;
    final spineClassText = exam['spine_class_text'] as String?;
    final isCervical = spineClass == 'cervical';
    final status = exam['status'] as String?;
    final imageUrl = exam['image_url'] as String?;
    final createdAt = exam['upload_date'] as String? ?? exam['created_at'] as String?;

    // Cervical metrics
    final cervicalRatio = (exam['cervical_avg_ratio'] as num?)?.toDouble();
    final cervicalAssessment = exam['cervical_assessment'] as String?;
    // Lumbar metrics
    final cobbAngle = (exam['cobb_angle'] as num?)?.toDouble();
    final severity = exam['severity_label'] as String?;
    // Common
    final improvement = (exam['improvement_value'] as num?)?.toDouble();

    final (statusLabel, statusColor) = _mapStatus(status);

    // Safe date
    String dateStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final l = dt.toLocal();
        dateStr = '${l.year}-${_p(l.month)}-${_p(l.day)}';
      } else {
        dateStr = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
      }
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline bar
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 0 ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                ),
                if (i < exams.length - 1)
                  Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/portal/exam/detail', extra: exam),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Thumbnail
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(Icons.image, color: theme.colorScheme.outline),
                                  ),
                                )
                              : Icon(Icons.image, color: theme.colorScheme.outline),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              if (spineClassText != null) Text(spineClassText, style: theme.textTheme.titleSmall),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            if (isCervical) ...[
                              if (cervicalRatio != null)
                                Text('前后比: ${cervicalRatio.toStringAsFixed(3)}'),
                              if (cervicalAssessment != null)
                                Text('评估: $cervicalAssessment', style: theme.textTheme.bodySmall),
                            ] else ...[
                              if (cobbAngle != null)
                                Text('Cobb角: ${cobbAngle.toStringAsFixed(1)}°'),
                              if (severity != null)
                                Text('严重程度: $severity', style: theme.textTheme.bodySmall),
                            ],
                            if (improvement != null)
                              Text(
                                improvement > 0 ? '↑ 改善 ${improvement.abs().toStringAsFixed(isCervical ? 3 : 1)}' : improvement < 0 ? '↓ 恶化 ${improvement.abs().toStringAsFixed(isCervical ? 3 : 1)}' : '— 无变化',
                                style: TextStyle(fontSize: 12, color: improvement > 0 ? AppColors.success : improvement < 0 ? AppColors.danger : theme.colorScheme.outline),
                              ),
                            if (dateStr.isNotEmpty)
                              Text(dateStr, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                          ],
                        )),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color) _mapStatus(String? status) {
    return switch (status) {
      'reviewed' => ('已复核', AppColors.success),
      'pending_review' => ('待复核', AppColors.primary),
      'inferring' => ('推理中', AppColors.warning),
      'inference_failed' => ('推理失败', AppColors.danger),
      'pending' => ('等待处理', AppColors.textHint),
      _ => ('处理中', AppColors.warning),
    };
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
