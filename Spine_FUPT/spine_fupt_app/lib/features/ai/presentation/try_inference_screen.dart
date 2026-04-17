import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../providers.dart';

class TryInferenceScreen extends ConsumerStatefulWidget {
  const TryInferenceScreen({super.key});
  @override
  ConsumerState<TryInferenceScreen> createState() => _TryInferenceScreenState();
}

class _TryInferenceScreenState extends ConsumerState<TryInferenceScreen> {
  File? _selectedImage;
  bool _uploading = false;
  bool _inferring = false;
  double _progress = 0;
  Map<String, dynamic>? _result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('上传影像'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview / picker
            if (_result == null) ...[
              AspectRatio(
                aspectRatio: 1,
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_selectedImage!, fit: BoxFit.contain),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickImage,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.outline),
                          ),
                          child: Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo, size: 64, color: theme.colorScheme.outline),
                              const SizedBox(height: 8),
                              const Text('点击选择X光影像'),
                              const SizedBox(height: 4),
                              Text('支持相册选择或拍照', style: theme.textTheme.bodySmall),
                            ],
                          )),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
            ],

            // Upload progress
            if (_uploading) ...[
              if (_inferring) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Center(child: Text('AI 分析中，请稍候...')),
              ] else ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Center(child: Text('上传中... ${(_progress * 100).toInt()}%')),
              ],
              const SizedBox(height: 16),
            ],

            // AI Result card
            if (_result != null) _buildResultCard(_result!, theme),

            // Action buttons
            if (!_uploading) ...[
              if (_result != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _askAi,
                  icon: const Icon(Icons.smart_toy),
                  label: const Text('向AI医生咨询'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => setState(() { _result = null; _selectedImage = null; }),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('继续上传'),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('选择图片'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selectedImage == null ? null : _upload,
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('上传'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result, ThemeData theme) {
    final spineClass = result['spine_class'] as String?;
    final spineClassText = result['spine_class_text'] as String?;
    final confidence = (result['spine_class_confidence'] as num?)?.toDouble();
    final isCervical = spineClass == 'cervical';

    // Lumbar metrics
    final cobbAngle = (result['cobb_angle'] as num?)?.toDouble();
    final curveValue = (result['curve_value'] as num?)?.toDouble();
    final severity = result['severity_label'] as String?;

    // Cervical metrics (anonymous returns nested cervical_metric)
    final cervicalMetric = result['cervical_metric'] as Map<String, dynamic>?;
    final cervicalRatio = (cervicalMetric?['avg_ratio'] as num?)?.toDouble();
    final cervicalAssessment = cervicalMetric?['assessment'] as String?;

    // Overlay image (base64)
    final overlayB64 = result['overlay_image'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Text('AI 分析完成',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.success)),
            ]),
            const SizedBox(height: 12),

            // AI annotated image
            if (overlayB64 != null && overlayB64.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(overlayB64),
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      height: 220, child: Center(child: Icon(Icons.broken_image))),
                ),
              ),
            if (overlayB64 != null && overlayB64.isNotEmpty)
              const SizedBox(height: 16),

            // Metrics table
            Text('量化指标', style: theme.textTheme.titleSmall),
            const Divider(),
            if (spineClassText != null) _ResultRow('影像分类', spineClassText),
            if (confidence != null)
              _ResultRow('置信度', '${(confidence * 100).toStringAsFixed(1)}%'),

            if (isCervical) ...[
              if (cervicalRatio != null)
                _ResultRow('平均前后比', cervicalRatio.toStringAsFixed(3)),
              if (cervicalAssessment != null)
                _ResultRow('颈椎评估', cervicalAssessment),
            ] else ...[
              if (cobbAngle != null)
                _ResultRow('Cobb 角', '${cobbAngle.toStringAsFixed(1)}°'),
              if (curveValue != null)
                _ResultRow('弯曲度', '${curveValue.toStringAsFixed(1)}°'),
              if (severity != null)
                _ResultRow('严重程度', severity),
            ],

            // Risk tips
            const SizedBox(height: 16),
            _buildRiskTip(theme, isCervical: isCervical, severity: severity,
                cervicalAssessment: cervicalAssessment, cobbAngle: cobbAngle,
                cervicalRatio: cervicalRatio),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskTip(ThemeData theme, {
    required bool isCervical,
    String? severity,
    String? cervicalAssessment,
    double? cobbAngle,
    double? cervicalRatio,
  }) {
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
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
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

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('拍照'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('从相册选择'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, maxWidth: 2048);
    if (xfile != null && mounted) {
      setState(() {
        _selectedImage = File(xfile.path);
        _result = null;
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedImage == null) return;
    setState(() { _uploading = true; _inferring = false; _progress = 0; _result = null; });

    try {
      final api = ApiClient.instance;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(_selectedImage!.path, filename: 'upload.jpg'),
      });

      final resp = await api.upload(
        ApiEndpoints.publicTryInference,
        formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            final p = sent / total;
            if (mounted && (p - _progress).abs() > 0.02) setState(() => _progress = p);
          }
          if (sent == total && !_inferring && mounted) {
            setState(() => _inferring = true);
          }
        },
      );

      if (resp['ok'] == true && resp['data'] != null) {
        if (mounted) {
          setState(() {
            _result = resp['data']['result'] as Map<String, dynamic>?;
            _selectedImage = null;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
            SnackBar(content: Text(resp['message'] ?? '推理失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          SnackBar(content: Text('上传失败: ${ApiClient.friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() { _uploading = false; _inferring = false; });
    }
  }

  void _askAi() {
    if (_result == null) return;
    final ctx = <String, dynamic>{
      'spine_class': _result!['spine_class'],
      'spine_class_text': _result!['spine_class_text'],
      'spine_class_confidence': _result!['spine_class_confidence'],
    };
    if (_result!['cobb_angle'] != null) ctx['cobb_angle'] = _result!['cobb_angle'];
    if (_result!['severity_label'] != null) ctx['severity_label'] = _result!['severity_label'];
    if (_result!['cervical_metric'] != null) ctx['cervical_metric'] = _result!['cervical_metric'];

    context.push('/trial/ai-doctor', extra: {'inference_context': ctx});
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);
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
