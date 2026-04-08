import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';

class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('通知动态')),
      body: overview.when(
        loading: () => const ShimmerNotificationList(),
        error: (e, _) => Center(child: Text('加载失败')),
        data: (data) {
          final feed = (data['feed'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (feed.isEmpty) {
            return const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none, size: 64, color: AppColors.textHint),
                SizedBox(height: 16),
                Text('暂无通知', style: TextStyle(color: AppColors.textHint)),
              ],
            ));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(overviewProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: feed.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = feed[i];
                final eventType = item['event_type'] as String? ?? '';
                final title = item['title'] as String? ?? '';
                final message = item['message'] as String? ?? '';
                final createdAt = item['created_at'] as String? ?? '';
                final ref2 = item['ref'] as Map<String, dynamic>? ?? {};
                final icon = _eventIcon(eventType);
                final time = _formatTime(createdAt);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: icon.$2.withValues(alpha: 0.15),
                    child: Icon(icon.$1, color: icon.$2, size: 20),
                  ),
                  title: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(time, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontSize: 11)),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () => _handleTap(context, eventType, item, ref2),
                );
              },
            ),
          );
        },
      ),
    );
  }

  (IconData, Color) _eventIcon(String type) {
    return switch (type) {
      'inference_result' => (Icons.auto_awesome, AppColors.success),
      'inference_failed' => (Icons.error_outline, AppColors.danger),
      'patient_created' || 'patient_registered' => (Icons.person_add, AppColors.primary),
      'patient_deleted' => (Icons.person_remove, AppColors.danger),
      'review_done' => (Icons.check_circle, AppColors.success),
      'review_deleted' => (Icons.delete, AppColors.danger),
      'review_queue_add' || 'xray_upload' => (Icons.photo_camera, AppColors.warning),
      'case_shared' => (Icons.link, AppColors.success),
      'case_shared_user' => (Icons.share, AppColors.info),
      'questionnaire_created' => (Icons.assignment_add, AppColors.info),
      'questionnaire_sent' => (Icons.send, AppColors.primary),
      'questionnaire_completed' => (Icons.assignment_turned_in, AppColors.success),
      'message' => (Icons.chat_bubble, AppColors.primary),
      'schedule' => (Icons.calendar_today, AppColors.warning),
      'xray_deleted' => (Icons.delete_forever, AppColors.danger),
      _ => (Icons.notifications, AppColors.textHint),
    };
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  void _handleTap(BuildContext context, String type, Map<String, dynamic> item, Map<String, dynamic> ref) {
    final patientId = item['patient_id'] ?? ref['patient_id'];
    final examId = item['exam_id'] ?? ref['exam_id'];
    final convId = ref['conversation_id'];
    final questionnaireId = ref['questionnaire_id'];

    switch (type) {
      case 'patient_created' || 'patient_registered':
        if (patientId != null) context.push('/doctor/patients/$patientId');
      case 'inference_result' || 'inference_failed' || 'review_done' || 'review_queue_add' || 'xray_upload':
        if (examId != null) context.push('/doctor/reviews/$examId');
      case 'case_shared_user' || 'message':
        if (convId != null) context.push('/doctor/chat/$convId');
      case 'case_shared':
        // Link-only share — no deep nav, just go to the overview
        if (examId != null) context.push('/doctor/reviews/$examId');
      case 'schedule':
        // Stay on overview which shows schedule section
        context.go('/doctor/overview');
      case 'questionnaire_created' || 'questionnaire_sent' || 'questionnaire_completed':
        if (questionnaireId != null) {
          context.push('/doctor/questionnaires/$questionnaireId');
        } else {
          context.go('/doctor/questionnaires');
        }
      default:
        break;
    }
  }
}
