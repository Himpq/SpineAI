import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers.dart';
import '../../../core/api/api_client.dart';

/// Create or edit a questionnaire. Pass [initialData] via GoRouter extra for edit mode.
class QuestionnaireEditScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialData;
  const QuestionnaireEditScreen({super.key, this.initialData});
  @override
  ConsumerState<QuestionnaireEditScreen> createState() => _QuestionnaireEditScreenState();
}

class _QuestionnaireEditScreenState extends ConsumerState<QuestionnaireEditScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final List<_QuestionItem> _questions = [];
  bool _saving = false;
  bool get _isEdit => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _titleCtrl.text = d['title']?.toString() ?? '';
      _descCtrl.text = d['description']?.toString() ?? '';
      final qs = d['questions'] as List? ?? [];
      for (final q in qs) {
        final m = q as Map<String, dynamic>;
        _questions.add(_QuestionItem(
          id: m['id'] is int ? m['id'] as int : null,
          type: m['q_type']?.toString() ?? 'single',
          title: m['title']?.toString() ?? '',
          options: (m['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
        ));
      }
    }
    if (_questions.isEmpty) {
      _questions.add(_QuestionItem(type: 'single', title: '', options: ['', '']));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑问卷' : '创建问卷'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '问卷标题 *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: '描述（可选）', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // Questions
          Row(children: [
            Text('题目列表', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _questions.add(_QuestionItem(type: 'single', title: '', options: ['', '']))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加题目'),
            ),
          ]),
          const Divider(),

          for (int i = 0; i < _questions.length; i++) ...[
            _QuestionEditor(
              index: i,
              item: _questions[i],
              onRemove: _questions.length > 1 ? () => setState(() => _questions.removeAt(i)) : null,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('请输入问卷标题')));
      return;
    }
    // Validate questions
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (q.title.trim().isEmpty) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(content: Text('第 ${i + 1} 题标题不能为空')));
        return;
      }
      if ((q.type == 'single' || q.type == 'multi') && q.options.where((o) => o.trim().isNotEmpty).length < 2) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(content: Text('第 ${i + 1} 题至少需要两个选项')));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'title': title,
        'description': _descCtrl.text.trim(),
        'questions': _questions.map((q) => {
          if (q.id != null) 'id': q.id,
          'q_type': q.type,
          'title': q.title.trim(),
          'options': (q.type == 'single' || q.type == 'multi')
              ? q.options.where((o) => o.trim().isNotEmpty).toList()
              : [],
        }).toList(),
      };

      final repo = ref.read(questionnaireRepoProvider);
      if (_isEdit) {
        final qid = widget.initialData!['id'] as int;
        final hasResponses = (widget.initialData!['response_count'] ?? 0) > 0;
        if (hasResponses) {
          await repo.safeEditQuestionnaire(qid, payload);
        } else {
          await repo.updateQuestionnaire(qid, payload);
        }
      } else {
        await repo.createQuestionnaire(payload);
      }

      ref.invalidate(questionnaireListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          SnackBar(content: Text(_isEdit ? '问卷已更新' : '问卷已创建')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          SnackBar(content: Text('保存失败: ${ApiClient.friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _QuestionItem {
  int? id; // null for new questions
  String type; // single | multi | text
  String title;
  List<String> options;
  _QuestionItem({this.id, required this.type, required this.title, required this.options});
}

class _QuestionEditor extends StatelessWidget {
  final int index;
  final _QuestionItem item;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  const _QuestionEditor({required this.index, required this.item, this.onRemove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
                child: Text('Q${index + 1}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('单选', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 'multi', label: Text('多选', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 'text', label: Text('文本', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {item.type},
                  onSelectionChanged: (v) {
                    item.type = v.first;
                    if (v.first == 'text') {
                      item.options = [];
                    } else if (item.options.length < 2) {
                      item.options = ['', ''];
                    }
                    onChanged();
                  },
                  style: ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ),
              if (onRemove != null)
                IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 20), onPressed: onRemove),
            ]),
            const SizedBox(height: 8),

            // Title
            TextFormField(
              initialValue: item.title,
              decoration: const InputDecoration(labelText: '题目', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => item.title = v,
            ),

            // Options (for single/multi)
            if (item.type == 'single' || item.type == 'multi') ...[
              const SizedBox(height: 8),
              for (int j = 0; j < item.options.length; j++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(item.type == 'multi' ? Icons.check_box_outline_blank : Icons.radio_button_unchecked,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue: item.options[j],
                          decoration: InputDecoration(hintText: '选项 ${j + 1}', isDense: true, border: InputBorder.none),
                          onChanged: (v) => item.options[j] = v,
                        ),
                      ),
                      if (item.options.length > 2)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            item.options.removeAt(j);
                            onChanged();
                          },
                          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    item.options.add('');
                    onChanged();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加选项', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
