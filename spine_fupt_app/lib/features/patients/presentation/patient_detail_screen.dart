import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';
import '../../models.dart';

final _patientDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  return ref.read(patientRepoProvider).getPatientDetail(id);
});

class PatientDetailScreen extends ConsumerStatefulWidget {
  final int patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  bool _refreshing = false;

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.refresh(_patientDetailProvider(widget.patientId).future);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('已刷新'), duration: Duration(seconds: 1)));
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(_patientDetailProvider(widget.patientId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('患者详情'),
        actions: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _doRefresh),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认删除'),
                    content: const Text('删除后将同时删除所有检查记录和聊天记录，不可恢复。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await ref.read(patientRepoProvider).deletePatient(widget.patientId);
                    ref.invalidate(patientListProvider);
                    if (context.mounted) context.pop();
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
                  }
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('删除患者')),
            ],
          ),
        ],
      ),
      body: detail.when(
        loading: () => const ShimmerPatientDetail(),
        error: (e, _) => Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(ApiClient.friendlyError(e), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            _refreshing
                ? const CircularProgressIndicator()
                : FilledButton(onPressed: _doRefresh, child: const Text('重试')),
          ],
        )),
        data: (data) {
          final patientData = data['patient'] as Map<String, dynamic>;
          final patient = PatientModel.fromJson(patientData);
          final exams = (patientData['exams'] as List? ?? []).map((e) => ExamModel.fromJson(e as Map<String, dynamic>)).toList();
          final trend = patientData['trend'] as List? ?? [];
          final portalUrl = patientData['portal_url'] as String?;
          final portalToken = patientData['portal_token'] as String?;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Patient info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(patient.name.isNotEmpty ? patient.name[0] : '?',
                                style: TextStyle(fontSize: 24, color: theme.colorScheme.primary)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(patient.name, style: theme.textTheme.titleLarge),
                                Text([
                                  if (patient.age != null) '${patient.age}岁',
                                  if (patient.sex != null) patient.sex!,
                                  if (patient.phone != null) patient.phone!,
                                ].join(' · '), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPatient(context, ref, patient),
                          ),
                        ],
                      ),
                      if (patient.note != null && patient.note!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('备注: ${patient.note}', style: theme.textTheme.bodySmall),
                      ],
                      if (portalUrl != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 16),
                            const SizedBox(width: 4),
                            Expanded(child: Text('患者门户已创建', style: theme.textTheme.bodySmall)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Quick actions
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChip(icon: Icons.add_a_photo, label: '上传影像', onTap: () => _uploadImage(context, ref)),
                  _ActionChip(icon: Icons.chat, label: '发起聊天', onTap: () => _startChat(context, ref, patient)),
                  _ActionChip(icon: Icons.calendar_today, label: '安排日程', onTap: () => _addSchedule(context, ref)),
                  if (portalToken != null)
                    _ActionChip(icon: Icons.qr_code, label: '患者二维码', onTap: () => _showPatientQr(context, portalToken, patient.name)),
                ],
              ),

              // Cobb trend
              if (trend.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Cobb角趋势', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _CobbTrendChart(trend: trend, theme: theme),
              ],

              // Timeline
              const SizedBox(height: 24),
              Text('检查记录 (${exams.length})', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (exams.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('暂无检查记录'))))
              else
                ...exams.map((exam) => _ExamTimelineItem(exam: exam, onDelete: () => _deleteExam(exam.id))),

              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  void _showPatientQr(BuildContext context, String portalToken, String patientName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$patientName 的二维码'),
        content: SizedBox(
          width: 260,
          height: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: portalToken,
                version: QrVersions.auto,
                size: 220,
              ),
              const SizedBox(height: 12),
              Text('患者扫此码可直接登录', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _uploadImage(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
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

    final picked = await picker.pickImage(source: source, maxWidth: 2048, imageQuality: 85);
    if (picked == null) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上传...')));
    }
    try {
      await ref.read(patientRepoProvider).uploadExam(widget.patientId, File(picked.path));
      ref.invalidate(_patientDetailProvider(widget.patientId));
      ref.invalidate(reviewListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功，推理中...')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
      }
    }
  }

  Future<void> _startChat(BuildContext context, WidgetRef ref, PatientModel patient) async {
    try {
      final conv = await ref.read(chatRepoProvider).createConversation(type: 'patient', patientId: patient.id);
      if (context.mounted) context.push('/doctor/chat/${conv.id}');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
    }
  }

  Future<void> _addSchedule(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    DateTime? date;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('安排日程'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date!) : '选择日期'),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null && ctx.mounted) {
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    setState(() => date = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isEmpty || date == null) return;
                try {
                  await ref.read(patientRepoProvider).createSchedule({
                    'patient_id': widget.patientId,
                    'title': titleCtrl.text,
                    'scheduled_at': date!.toIso8601String(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _editPatient(BuildContext context, WidgetRef ref, PatientModel patient) {
    final nameCtrl = TextEditingController(text: patient.name);
    final ageCtrl = TextEditingController(text: patient.age?.toString() ?? '');
    String? sex = patient.sex;
    final phoneCtrl = TextEditingController(text: patient.phone ?? '');
    final emailCtrl = TextEditingController(text: patient.email ?? '');
    final noteCtrl = TextEditingController(text: patient.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑患者'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名')),
                const SizedBox(height: 12),
                TextField(controller: ageCtrl, decoration: const InputDecoration(labelText: '年龄'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: sex,
                  decoration: const InputDecoration(labelText: '性别'),
                  items: const [
                    DropdownMenuItem(value: '男', child: Text('男')),
                    DropdownMenuItem(value: '女', child: Text('女')),
                  ],
                  onChanged: (v) => setDialogState(() => sex = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '电话'), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: '邮箱'), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: '备注'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(patientRepoProvider).updatePatient(widget.patientId, {
                    'name': nameCtrl.text.trim(),
                    if (ageCtrl.text.isNotEmpty) 'age': int.tryParse(ageCtrl.text),
                    'sex': sex,
                    'phone': phoneCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'note': noteCtrl.text.trim(),
                  });
                  ref.invalidate(_patientDetailProvider(widget.patientId));
                  ref.invalidate(patientListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExam(int examId) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除检查'),
        content: const Text('删除后不可恢复，关联的分享链接和评论也将一并删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(reviewRepoProvider).deleteReview(examId);
      ref.invalidate(_patientDetailProvider(widget.patientId));
      ref.invalidate(reviewListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查记录已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
      }
    }
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

class _ExamTimelineItem extends StatelessWidget {
  final ExamModel exam;
  final VoidCallback? onDelete;
  const _ExamTimelineItem({required this.exam, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color statusColor;
    String statusLabel;
    switch (exam.status) {
      case 'reviewed':
        statusColor = AppColors.success;
        statusLabel = '已复核';
        break;
      case 'inference_failed':
        statusColor = AppColors.danger;
        statusLabel = '推理失败';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = '待复核';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/doctor/reviews/${exam.id}'),
        onLongPress: onDelete == null
            ? null
            : () async {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(Icons.delete, color: theme.colorScheme.error),
                          title: Text('删除检查记录', style: TextStyle(color: theme.colorScheme.error)),
                          onTap: () => Navigator.pop(ctx, 'delete'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.cancel),
                          title: const Text('取消'),
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                );
                if (action == 'delete') onDelete!();
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Timeline dot
              Column(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(exam.createdAt?.substring(0, 10) ?? '', style: theme.textTheme.bodySmall),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                          child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (exam.spineClassText != null)
                          Text('${exam.spineClassText} ', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (exam.cobbAngle != null)
                          Text('Cobb: ${exam.cobbAngle!.toStringAsFixed(1)}°', style: theme.textTheme.bodyMedium),
                        if (exam.severityLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(exam.severityLabel!, style: TextStyle(color: _severityColor(exam.severityLabel!), fontSize: 13)),
                        ],
                      ],
                    ),
                    if (exam.improvementValue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '较前次 ${exam.improvementValue! > 0 ? '+' : ''}${exam.improvementValue!.toStringAsFixed(1)}°',
                        style: TextStyle(
                          color: exam.improvementValue! < 0 ? AppColors.success : AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(String label) {
    if (label.contains('重度')) return AppColors.danger;
    if (label.contains('中度')) return AppColors.warning;
    if (label.contains('轻度')) return AppColors.warning;
    return AppColors.success;
  }
}

class _CobbTrendChart extends StatelessWidget {
  final List trend;
  final ThemeData theme;
  const _CobbTrendChart({required this.trend, required this.theme});

  @override
  Widget build(BuildContext context) {
    final values = trend.map((t) => (t['cobb_angle'] as num?)?.toDouble() ?? 0).toList();
    final maxVal = values.reduce((a, b) => a > b ? a : b).clamp(10, 90).toDouble();
    const barAreaHeight = 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: barAreaHeight + 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(trend.length, (i) {
              final val = values[i];
              final barH = (val / maxVal * barAreaHeight).clamp(4.0, barAreaHeight);
              final dateStr = trend[i]['date']?.toString();
              final label = dateStr != null && dateStr.length >= 10 ? dateStr.substring(5, 10) : '';
              Color barColor;
              if (val >= 40) {
                barColor = AppColors.danger;
              } else if (val >= 25) {
                barColor = AppColors.warning;
              } else if (val >= 10) {
                barColor = AppColors.warning;
              } else {
                barColor = AppColors.success;
              }
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${val.toStringAsFixed(0)}°',
                          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10)),
                      const SizedBox(height: 2),
                      Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
