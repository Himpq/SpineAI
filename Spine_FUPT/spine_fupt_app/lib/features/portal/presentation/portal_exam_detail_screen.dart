import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

/// Portal exam detail screen — receives exam map via GoRouter extra.
class PortalExamDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> exam;
  const PortalExamDetailScreen({super.key, required this.exam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseUrl = ref.read(serverUrlProvider);

    final status = exam['status'] as String?;
    final spineClass = exam['spine_class'] as String?;
    final spineClassText = exam['spine_class_text'] as String?;
    final confidence = (exam['spine_class_confidence'] as num?)?.toDouble();
    final isCervical = spineClass == 'cervical';

    // Lumbar
    final cobbAngle = (exam['cobb_angle'] as num?)?.toDouble();
    final curveValue = (exam['curve_value'] as num?)?.toDouble();
    final severity = exam['severity_label'] as String?;

    // Cervical
    final cervicalRatio = (exam['cervical_avg_ratio'] as num?)?.toDouble();
    final cervicalAssessment = exam['cervical_assessment'] as String?;

    // Common
    final improvement = (exam['improvement_value'] as num?)?.toDouble();
    final reviewNote = exam['review_note'] as String?;
    final reviewedAt = exam['reviewed_at'] as String?;
    final createdAt = exam['upload_date'] as String? ?? exam['created_at'] as String?;

    // Images
    final inferenceUrl = exam['inference_image_url'] as String?;
    final rawUrl = exam['raw_image_url'] ?? exam['image_url'];

    String? fullUrl(String? url) {
      if (url == null) return null;
      return url.startsWith('http') ? url : '$baseUrl$url';
    }

    final displayImage = fullUrl(inferenceUrl) ?? fullUrl(rawUrl as String?);

    // Date formatting
    String dateStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final local = dt.toLocal();
        dateStr = '${local.year}-${_p(local.month)}-${_p(local.day)} ${_p(local.hour)}:${_p(local.minute)}';
      } else {
        dateStr = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
      }
    }

    // Status
    final (statusLabel, statusColor) = _mapStatus(status);

    return Scaffold(
      appBar: AppBar(title: const Text('检查详情')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image ──
            if (displayImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(displayImage, height: 260, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      height: 260, child: Center(child: Icon(Icons.broken_image, size: 48))),
                ),
              ),
            const SizedBox(height: 16),

            // ── Status & date row ──
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              if (dateStr.isNotEmpty)
                Text(dateStr, style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
            ]),
            const SizedBox(height: 16),

            // ── Metrics card ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('量化指标', style: theme.textTheme.titleSmall),
                    const Divider(),
                    if (spineClassText != null)
                      _Row('影像分类', spineClassText),
                    if (confidence != null)
                      _Row('置信度', '${(confidence * 100).toStringAsFixed(1)}%'),

                    if (isCervical) ...[
                      if (cervicalRatio != null)
                        _Row('平均前后比', cervicalRatio.toStringAsFixed(3)),
                      if (cervicalAssessment != null)
                        _Row('颈椎评估', cervicalAssessment),
                    ] else ...[
                      if (cobbAngle != null)
                        _Row('Cobb 角', '${cobbAngle.toStringAsFixed(1)}°'),
                      if (curveValue != null)
                        _Row('弯曲度', '${curveValue.toStringAsFixed(1)}°'),
                      if (severity != null)
                        _Row('严重程度', severity),
                    ],

                    if (improvement != null)
                      _Row('与上次对比', improvement > 0
                          ? '改善 ${improvement.abs().toStringAsFixed(isCervical ? 3 : 1)}${isCervical ? "" : "°"}'
                          : improvement < 0
                              ? '恶化 ${improvement.abs().toStringAsFixed(isCervical ? 3 : 1)}${isCervical ? "" : "°"}'
                              : '无变化'),
                  ],
                ),
              ),
            ),

            // ── Risk tip ──
            const SizedBox(height: 12),
            _buildRiskTip(theme, isCervical: isCervical, severity: severity,
                cervicalAssessment: cervicalAssessment),

            // ── Ask AI button ──
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                final ctx = <String, dynamic>{
                  'spine_class': spineClass,
                  'spine_class_text': spineClassText,
                  'spine_class_confidence': confidence,
                };
                if (cobbAngle != null) ctx['cobb_angle'] = cobbAngle;
                if (severity != null) ctx['severity_label'] = severity;
                if (cervicalRatio != null) ctx['cervical_avg_ratio'] = cervicalRatio;
                if (cervicalAssessment != null) ctx['cervical_assessment'] = cervicalAssessment;
                context.push('/ai-doctor', extra: {'inference_context': ctx});
              },
              icon: const Icon(Icons.smart_toy),
              label: const Text('向AI医生咨询本次检查'),
            ),

            // ── Doctor review ──
            if (reviewNote != null && reviewNote.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.medical_services, size: 18),
                        const SizedBox(width: 8),
                        Text('医师复核意见', style: theme.textTheme.titleSmall),
                      ]),
                      const SizedBox(height: 8),
                      Text(reviewNote),
                      if (reviewedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(_formatDate(reviewedAt),
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
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

  static Widget _buildRiskTip(ThemeData theme,
      {required bool isCervical, String? severity, String? cervicalAssessment}) {
    String tip;
    Color bgColor;
    IconData icon;

    if (isCervical) {
      if (cervicalAssessment == '良好') {
        tip = '您的颈椎前后比在正常范围（0.83~1.11），状态良好。建议保持正确坐姿，定期复查。';
        bgColor = AppColors.successLight;
        icon = Icons.health_and_safety;
      } else if (cervicalAssessment != null && cervicalAssessment.contains('颈痛')) {
        tip = '前后比偏低，颈椎抗过载能力减弱，容易出现颈部疼痛。建议加强颈部肌肉锻炼并尽早就诊。';
        bgColor = AppColors.warningLight;
        icon = Icons.warning_amber;
      } else if (cervicalAssessment != null && cervicalAssessment.contains('颈椎疾病')) {
        tip = '前后比偏高，存在颈椎疾病风险。建议尽快前往医院进行进一步检查和治疗。';
        bgColor = AppColors.dangerLight;
        icon = Icons.error_outline;
      } else {
        tip = '暂无法评估，请确保影像清晰后重新上传或咨询医生。';
        bgColor = AppColors.bgSecondary;
        icon = Icons.info_outline;
      }
    } else {
      if (severity == '重度') {
        tip = 'Cobb 角 ≥ 40°，属于重度侧弯。强烈建议尽快就医，可能需要手术干预。';
        bgColor = AppColors.dangerLight;
        icon = Icons.error_outline;
      } else if (severity == '中度') {
        tip = 'Cobb 角在 20°~40° 之间，属于中度侧弯。建议佩戴矫形支具并定期复查。';
        bgColor = AppColors.warningLight;
        icon = Icons.warning_amber;
      } else if (severity == '轻度') {
        tip = 'Cobb 角 < 20°，属于轻度侧弯。建议通过运动矫正并每 6 个月复查。';
        bgColor = AppColors.successLight;
        icon = Icons.health_and_safety;
      } else {
        tip = '分析完成，具体治疗方案请咨询您的主治医生。';
        bgColor = AppColors.bgSecondary;
        icon = Icons.info_outline;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tip, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  static String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final l = dt.toLocal();
    return '${l.year}-${_p(l.month)}-${_p(l.day)} ${_p(l.hour)}:${_p(l.minute)}';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textHint)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
