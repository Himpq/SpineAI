import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';
import '../../../core/api/api_client.dart';

class QuestionnaireDetailScreen extends ConsumerStatefulWidget {
  final int questionnaireId;
  const QuestionnaireDetailScreen({super.key, required this.questionnaireId});
  @override
  ConsumerState<QuestionnaireDetailScreen> createState() => _QuestionnaireDetailScreenState();
}

class _QuestionnaireDetailScreenState extends ConsumerState<QuestionnaireDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _responses;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await ref.read(questionnaireRepoProvider).getQuestionnaire(widget.questionnaireId);
      final responses = await ref.read(questionnaireRepoProvider).getResponses(widget.questionnaireId);
      if (mounted) setState(() { _detail = detail; _responses = responses; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?['title']?.toString() ?? '问卷详情'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => _loading = true); _load(); }),
          if (_detail != null) PopupMenuButton<String>(
            onSelected: (v) => _handleAction(v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑问卷')),
              if (_detail!['status'] == 'active')
                const PopupMenuItem(value: 'stop', child: Text('终止问卷')),
              const PopupMenuItem(value: 'delete', child: Text('删除问卷')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '题目'),
            Tab(text: '回收'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('加载失败'))
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildOverviewTab(theme),
                    _buildQuestionsTab(theme),
                    _buildResponsesTab(theme),
                  ],
                ),
      floatingActionButton: (_detail != null && _detail!['status'] == 'active')
          ? FloatingActionButton.extended(
              onPressed: () => _showAssignDialog(),
              icon: const Icon(Icons.send),
              label: const Text('发送给患者'),
            )
          : null,
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    final d = _detail!;
    final isActive = d['status'] == 'active';
    final completedCount = d['completed_count'] ?? 0;
    final pendingCount = d['pending_count'] ?? 0;
    final responseCount = d['response_count'] ?? 0;
    final assignmentCount = d['assignment_count'] ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.success.withOpacity(0.1) : AppColors.textHint.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? '进行中' : '已终止',
                        style: TextStyle(color: isActive ? AppColors.success : AppColors.textHint, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Spacer(),
                    Text('创建于 ${_formatDate(d['created_at']?.toString())}', style: theme.textTheme.bodySmall),
                  ],
                ),
                if (d['description'] != null && d['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(d['description'].toString(), style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Stats row
        Row(
          children: [
            _MiniStat(label: '已发送', value: '$assignmentCount', icon: Icons.send, color: AppColors.primary),
            const SizedBox(width: 8),
            _MiniStat(label: '已完成', value: '$completedCount', icon: Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            _MiniStat(label: '待填写', value: '$pendingCount', icon: Icons.pending, color: AppColors.warning),
            const SizedBox(width: 8),
            _MiniStat(label: '回收数', value: '$responseCount', icon: Icons.inbox, color: AppColors.info),
          ],
        ),
        const SizedBox(height: 16),

        // Time range
        if (d['open_from'] != null || d['open_until'] != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('开放时间'),
              subtitle: Text([
                if (d['open_from'] != null) '从 ${_formatDate(d['open_from']?.toString())}',
                if (d['open_until'] != null) '至 ${_formatDate(d['open_until']?.toString())}',
              ].join(' ')),
            ),
          ),

        // Stats charts
        if (_responses != null && (_responses!['stats'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text('统计概览', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...(_responses!['stats'] as List).map((stat) => _StatCard(stat: stat as Map<String, dynamic>)),
        ],
      ],
    );
  }

  Widget _buildQuestionsTab(ThemeData theme) {
    final questions = _detail!['questions'] as List? ?? [];
    if (questions.isEmpty) {
      return const Center(child: Text('暂无题目'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (_, i) {
        final q = questions[i] as Map<String, dynamic>;
        final qType = q['q_type']?.toString() ?? 'text';
        final options = q['options'] as List? ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Q${i + 1}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                    ),
                    const SizedBox(width: 8),
                    _TypeBadge(qType),
                  ],
                ),
                const SizedBox(height: 8),
                Text(q['title']?.toString() ?? '', style: theme.textTheme.bodyLarge),
                if (options.isNotEmpty && (qType == 'single' || qType == 'multi' || qType == 'choice')) ...[
                  const SizedBox(height: 8),
                  ...options.map((opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          qType == 'multi' ? Icons.check_box_outline_blank : Icons.radio_button_unchecked,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(opt.toString(), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )),
                ],
                if (qType == 'text' || qType == 'blank') ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('填写区域', style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResponsesTab(ThemeData theme) {
    final responses = (_responses?['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (responses.isEmpty) {
      return const Center(child: Text('暂无回收记录'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: responses.length,
      itemBuilder: (_, i) {
        final r = responses[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(r['responder']?.toString() ?? r['patient_name']?.toString() ?? '匿名'),
            subtitle: Text('提交时间: ${_formatDate(r['submitted_at']?.toString())}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _showResponseDetail(r['id'] as int),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                  onPressed: () => _confirmDeleteResponse(r['id'] as int),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showResponseDetail(int responseId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final detail = await ref.read(questionnaireRepoProvider).getResponseDetail(widget.questionnaireId, responseId);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final answers = detail['answers'] as List? ?? [];
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${detail['responder_name'] ?? '匿名'} 的回答'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: answers.length,
              itemBuilder: (_, i) {
                final a = answers[i] as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Q${i + 1}: ${a['question_title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(_formatAnswer(a['answer']), style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  String _formatAnswer(dynamic answer) {
    if (answer == null) return '(未作答)';
    if (answer is List) return answer.join(', ');
    return answer.toString();
  }

  void _confirmDeleteResponse(int responseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除回收记录'),
        content: const Text('确定要删除这条回收记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(questionnaireRepoProvider).deleteResponse(widget.questionnaireId, responseId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
          setState(() => _loading = true);
          _load();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  void _showAssignDialog() async {
    // Load patient list
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final patients = await ref.read(patientRepoProvider).getPatients();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final selected = <int>{};
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('选择患者'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: patients.isEmpty
                  ? const Center(child: Text('暂无患者'))
                  : ListView.builder(
                      itemCount: patients.length,
                      itemBuilder: (_, i) {
                        final p = patients[i];
                        return CheckboxListTile(
                          title: Text(p.name),
                          subtitle: Text([
                            if (p.age != null) '${p.age}岁',
                            if (p.sex != null) p.sex!,
                          ].join(' ')),
                          value: selected.contains(p.id),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) { selected.add(p.id); } else { selected.remove(p.id); }
                          }),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () async {
                  Navigator.pop(ctx);
                  try {
                    final assignments = await ref.read(questionnaireRepoProvider).assignQuestionnaire(
                      widget.questionnaireId,
                      selected.toList(),
                    );
                    if (mounted) {
                      ref.invalidate(questionnaireListProvider);
                      setState(() => _loading = true);
                      _load();
                      // Show links dialog
                      _showAssignmentLinks(assignments);
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
                  }
                },
                child: Text('发送 (${selected.length})'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载患者列表失败: $e')));
    }
  }

  void _showAssignmentLinks(List<dynamic> assignments) {
    final serverUrl = ref.read(serverUrlProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('已发送给 ${assignments.length} 位患者'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: assignments.length,
            itemBuilder: (_, i) {
              final a = assignments[i];
              final token = a['token'] ?? '';
              final url = '$serverUrl/q/$token';
              final patientName = a['patient_name'] ?? '患者${a['patient_id']}';
              return ListTile(
                title: Text(patientName),
                subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制 $patientName 的链接')),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final all = assignments.map((a) {
                final name = a['patient_name'] ?? '患者${a['patient_id']}';
                return '$name: $serverUrl/q/${a['token']}';
              }).join('\n');
              Clipboard.setData(ClipboardData(text: all));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制全部链接')),
              );
            },
            child: const Text('复制全部'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _handleAction(String action) async {
    if (action == 'edit') {
      context.push('/doctor/questionnaires/edit', extra: _detail);
      return;
    }
    if (action == 'stop') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('终止问卷'),
          content: const Text('终止后将不再接收新的回答。已收集的数据不受影响。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('终止')),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await ref.read(questionnaireRepoProvider).stopQuestionnaire(widget.questionnaireId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('问卷已终止')));
            ref.invalidate(questionnaireListProvider);
            setState(() => _loading = true);
            _load();
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除问卷'),
          content: const Text('删除后所有数据（包括回收记录）将永久丢失，不可恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await ref.read(questionnaireRepoProvider).deleteQuestionnaire(widget.questionnaireId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('问卷已删除')));
            ref.invalidate(questionnaireListProvider);
            Navigator.of(context).pop();
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      return iso.substring(0, 10);
    } catch (_) {
      return iso;
    }
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String qType;
  const _TypeBadge(this.qType);

  @override
  Widget build(BuildContext context) {
    String label;
    switch (qType) {
      case 'single': label = '单选'; break;
      case 'multi': label = '多选'; break;
      case 'choice': label = '选择'; break;
      case 'text': label = '文本'; break;
      case 'blank': label = '填空'; break;
      default: label = qType;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = stat['distribution'] as Map<String, dynamic>? ?? {};
    final total = stat['total'] ?? 0;
    final qType = stat['q_type']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TypeBadge(qType),
                const SizedBox(width: 8),
                Expanded(child: Text(stat['title']?.toString() ?? '', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
                Text('$total 回答', style: theme.textTheme.bodySmall),
              ],
            ),
            if (distribution.isNotEmpty && (qType == 'single' || qType == 'multi' || qType == 'choice')) ...[
              const SizedBox(height: 8),
              ...distribution.entries.map((e) {
                final count = e.value as int? ?? 0;
                final pct = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 80, child: Text(e.key, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 40, child: Text('$count', style: theme.textTheme.bodySmall, textAlign: TextAlign.end)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
