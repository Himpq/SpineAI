import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';

class QuestionnaireListScreen extends ConsumerStatefulWidget {
  const QuestionnaireListScreen({super.key});
  @override
  ConsumerState<QuestionnaireListScreen> createState() => _QuestionnaireListScreenState();
}

class _QuestionnaireListScreenState extends ConsumerState<QuestionnaireListScreen> {
  String _filter = 'all'; // all | active | stopped

  @override
  Widget build(BuildContext context) {
    final questionnaires = ref.watch(questionnaireListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('问卷管理'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            ref.invalidate(questionnaireListProvider);
            ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新')));
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/doctor/questionnaires/create'),
        icon: const Icon(Icons.add),
        label: const Text('创建问卷'),
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _FilterChip(label: '全部', value: 'all', selected: _filter, onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: '进行中', value: 'active', selected: _filter, onTap: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: '已终止', value: 'stopped', selected: _filter, onTap: (v) => setState(() => _filter = v)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: questionnaires.when(
              loading: () => const ShimmerQuestionnaireList(),
              error: (e, _) => Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败: ${ApiClient.friendlyError(e)}'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: () => ref.invalidate(questionnaireListProvider), child: const Text('重试')),
                ],
              )),
              data: (list) {
                final filtered = _filter == 'all' ? list : list.where((q) => q['status'] == _filter).toList();
                if (filtered.isEmpty) {
                  return Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_outlined, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(list.isEmpty ? '暂无问卷' : '无匹配问卷'),
                    ],
                  ));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(questionnaireListProvider);
                    // Wait for the provider to finish loading
                    await ref.read(questionnaireListProvider.future);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新')));
                    }
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _QuestionnaireTile(q: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(value),
      showCheckmark: false,
    );
  }
}

class _QuestionnaireTile extends StatelessWidget {
  final Map<String, dynamic> q;
  const _QuestionnaireTile({required this.q});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = q['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final responseCount = q['response_count'] ?? 0;
    final assignmentCount = q['assignment_count'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? AppColors.successLight : AppColors.bgSecondary,
          child: Icon(
            isActive ? Icons.assignment : Icons.assignment_late,
            color: isActive ? AppColors.success : AppColors.textHint,
          ),
        ),
        title: Text(q['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Icon(Icons.people_outline, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text('$assignmentCount', style: theme.textTheme.bodySmall),
            const SizedBox(width: 12),
            Icon(Icons.check_circle_outline, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text('$responseCount', style: theme.textTheme.bodySmall),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isActive ? AppColors.success.withOpacity(0.1) : AppColors.textHint.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? '进行中' : '已终止',
                style: TextStyle(fontSize: 11, color: isActive ? AppColors.success : AppColors.textHint),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/doctor/questionnaires/${q['id']}'),
      ),
    );
  }
}
