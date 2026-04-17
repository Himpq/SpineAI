import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';

class PublicQuestionnaireScreen extends ConsumerStatefulWidget {
  final String token;
  const PublicQuestionnaireScreen({super.key, required this.token});
  @override
  ConsumerState<PublicQuestionnaireScreen> createState() => _PublicQuestionnaireScreenState();
}

class _PublicQuestionnaireScreenState extends ConsumerState<PublicQuestionnaireScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitted = false;
  bool _submitting = false;
  String? _error;
  final Map<int, dynamic> _answers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(portalRepoProvider).getPublicQuestionnaire(widget.token);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('无法加载问卷', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodyMedium),
            ],
          ),
        )),
      );
    }
    if (_submitted) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 64, color: AppColors.success),
              const SizedBox(height: 16),
              Text('提交成功', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('感谢您的填写！'),
            ],
          ),
        )),
      );
    }

    final questionnaire = _data!['questionnaire'] as Map<String, dynamic>? ?? {};
    final questions = questionnaire['questions'] as List? ?? [];
    final assignment = _data!['assignment'] as Map<String, dynamic>? ?? {};

    // Check if already submitted
    if (assignment['already_submitted'] == true) {
      return Scaffold(
        appBar: AppBar(title: Text(questionnaire['title']?.toString() ?? '问卷')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 64, color: AppColors.success),
              const SizedBox(height: 16),
              Text('您已提交过该问卷', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('每份问卷只能提交一次。'),
            ],
          ),
        )),
      );
    }

    // Check if questionnaire is stopped or not in open window
    final qStatus = questionnaire['status']?.toString();
    final openOk = questionnaire['open_ok'];
    if (qStatus == 'stopped') {
      return Scaffold(
        appBar: AppBar(title: Text(questionnaire['title']?.toString() ?? '问卷')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('问卷已终止', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('该问卷已停止收集，无法填写。'),
            ],
          ),
        )),
      );
    }
    if (openOk == false) {
      return Scaffold(
        appBar: AppBar(title: Text(questionnaire['title']?.toString() ?? '问卷')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 64, color: AppColors.warning),
              const SizedBox(height: 16),
              Text('问卷未开放', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('该问卷不在开放时间范围内。'),
            ],
          ),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(questionnaire['title']?.toString() ?? '问卷')),
      body: Column(
        children: [
          if (assignment['patient_name'] != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              child: Text('${assignment['patient_name']}，请填写以下问卷', style: theme.textTheme.bodyMedium),
            ),
          Expanded(
            child: questions.isEmpty
                ? const Center(child: Text('该问卷暂无题目'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: questions.length + 1, // +1 for submit button
                    itemBuilder: (_, i) {
                      if (i == questions.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                            label: Text(_submitting ? '提交中...' : '提交问卷'),
                          ),
                        );
                      }
                      return _QuestionWidget(
                        index: i,
                        question: questions[i] as Map<String, dynamic>,
                        answer: _answers[questions[i]['id'] as int? ?? i],
                        onChanged: (val) => setState(() => _answers[questions[i]['id'] as int? ?? i] = val),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    // Validate all questions answered
    final questionnaire = _data!['questionnaire'] as Map<String, dynamic>? ?? {};
    final questions = questionnaire['questions'] as List? ?? [];
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i] as Map<String, dynamic>;
      final qid = q['id'] as int? ?? i;
      final ans = _answers[qid];
      if (ans == null || (ans is String && ans.trim().isEmpty) || (ans is List && ans.isEmpty)) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          SnackBar(content: Text('请先回答第 ${i + 1} 题')),
        );
        return;
      }
    }
    setState(() => _submitting = true);
    final answersPayload = <String, dynamic>{};
    _answers.forEach((k, v) => answersPayload[k.toString()] = v);
    try {
      await ref.read(portalRepoProvider).submitQuestionnaire(widget.token, {'answers': answersPayload});
      if (mounted) setState(() { _submitted = true; _submitting = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败: $e')));
      }
    }
  }
}

class _QuestionWidget extends StatelessWidget {
  final int index;
  final Map<String, dynamic> question;
  final dynamic answer;
  final ValueChanged<dynamic> onChanged;
  const _QuestionWidget({required this.index, required this.question, required this.answer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qType = question['q_type']?.toString() ?? 'text';
    final options = (question['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final title = question['title']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. $title', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (qType == 'single' || qType == 'choice')
              ...options.map((opt) => RadioListTile<String>(
                value: opt,
                groupValue: answer?.toString(),
                title: Text(opt),
                onChanged: (v) => onChanged(v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              )),
            if (qType == 'multi')
              ...options.map((opt) {
              final selected = List<String>.from((answer as List?) ?? []);
                return CheckboxListTile(
                  value: selected.contains(opt),
                  title: Text(opt),
                  onChanged: (v) {
                    final current = List<String>.from(selected);
                    if (v == true) {
                      current.add(opt);
                    } else {
                      current.remove(opt);
                    }
                    onChanged(current);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              }),
            if (qType == 'text' || qType == 'blank')
              TextFormField(
                initialValue: answer?.toString() ?? '',
                maxLines: qType == 'text' ? 3 : 1,
                decoration: InputDecoration(
                  hintText: qType == 'text' ? '请输入您的回答...' : '请填写',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => onChanged(v),
              ),
          ],
        ),
      ),
    );
  }
}
