import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// NDI 颈椎功能障碍指数问卷
class NdiQuestionnaireScreen extends StatefulWidget {
  const NdiQuestionnaireScreen({super.key});
  @override
  State<NdiQuestionnaireScreen> createState() => _NdiQuestionnaireScreenState();
}

class _NdiQuestionnaireScreenState extends State<NdiQuestionnaireScreen> {
  int _currentPage = 0;
  final Map<int, int> _answers = {};
  bool _showResult = false;

  static const _questions = <_Q>[
    _Q(
      title: '第一部分：疼痛程度',
      options: [
        '我现在没有疼痛',
        '目前疼痛非常轻微',
        '目前疼痛中等',
        '目前疼痛比较严重',
        '目前疼痛非常严重',
        '目前疼痛是能想象到的最严重程度',
      ],
    ),
    _Q(
      title: '第二部分：个人护理（洗漱、穿衣等）',
      options: [
        '我能正常照顾自己而不会引起额外的疼痛',
        '我能正常照顾自己但会引起额外的疼痛',
        '照顾自己很痛苦，我需要缓慢小心地进行',
        '我需要一些帮助但能完成大部分个人护理',
        '我在大多数个人护理方面都需要帮助',
        '我无法自己穿衣，洗漱也很困难',
      ],
    ),
    _Q(
      title: '第三部分：提举重物',
      options: [
        '我能提起重物而不会额外疼痛',
        '我能提起重物但会引起额外疼痛',
        '疼痛使我无法从地面提起重物，但放在方便位置的可以',
        '疼痛使我无法提起重物，但轻到中等重量放在方便位置的可以',
        '我只能提很轻的东西',
        '我完全不能提任何东西',
      ],
    ),
    _Q(
      title: '第四部分：阅读',
      options: [
        '阅读时颈部完全没有疼痛',
        '想读多久就读多久，颈部有轻微疼痛',
        '想读多久就读多久，颈部有中等疼痛',
        '因为颈部中等疼痛无法长时间阅读',
        '因为颈部剧烈疼痛几乎无法阅读',
        '完全无法阅读',
      ],
    ),
    _Q(
      title: '第五部分：头痛',
      options: [
        '完全没有头痛',
        '偶尔轻微头痛',
        '偶尔中等程度头痛',
        '频繁中等程度头痛',
        '频繁严重头痛',
        '几乎一直头痛',
      ],
    ),
    _Q(
      title: '第六部分：注意力集中',
      options: [
        '需要时能完全集中注意力',
        '需要时能完全集中注意力但有轻微困难',
        '集中注意力有中等程度的困难',
        '集中注意力有很大困难',
        '集中注意力有极大困难',
        '完全无法集中注意力',
      ],
    ),
    _Q(
      title: '第七部分：工作',
      options: [
        '可以做想做的任何工作',
        '只能做平时的工作，不能更多',
        '能做大部分平时的工作，不能更多',
        '无法做平时的工作',
        '几乎无法做任何工作',
        '完全不能工作',
      ],
    ),
    _Q(
      title: '第八部分：驾驶',
      options: [
        '驾驶时颈部不疼',
        '驾驶时颈部轻微疼痛',
        '驾驶时颈部中等疼痛',
        '因颈部中等疼痛无法长时间驾驶',
        '因颈部剧烈疼痛几乎不能驾驶',
        '完全不能驾驶',
      ],
    ),
    _Q(
      title: '第九部分：睡眠',
      options: [
        '睡眠完全没有问题',
        '睡眠轻微受到干扰（失眠少于1小时）',
        '睡眠中等程度受到干扰（失眠1-2小时）',
        '睡眠较明显受到干扰（失眠2-3小时）',
        '睡眠严重受到干扰（失眠3-5小时）',
        '睡眠完全受干扰（失眠5-7小时）',
      ],
    ),
    _Q(
      title: '第十部分：娱乐活动',
      options: [
        '能参加所有的娱乐活动，颈部完全不痛',
        '能参加所有的娱乐活动，颈部有些疼痛',
        '能参加大部分娱乐活动，因颈痛受限',
        '因颈痛只能参加少数娱乐活动',
        '因颈痛几乎无法参加任何娱乐活动',
        '完全无法参加任何娱乐活动',
      ],
    ),
  ];

  int get _totalScore {
    int s = 0;
    for (final e in _answers.entries) s += e.value;
    return s;
  }

  double get _percentage => _totalScore / 50 * 100;

  String get _levelText {
    final p = _percentage;
    if (p <= 20) return '轻度功能障碍';
    if (p <= 40) return '中度功能障碍';
    if (p <= 60) return '重度功能障碍';
    if (p <= 80) return '严重功能障碍';
    return '完全功能障碍';
  }

  Color get _levelColor {
    final p = _percentage;
    if (p <= 20) return AppColors.success;
    if (p <= 40) return AppColors.warning;
    if (p <= 60) return const Color(0xFFFF9500);
    return AppColors.danger;
  }

  List<String> get _suggestions {
    final p = _percentage;
    if (p <= 20) {
      return ['颈椎功能基本正常', '注意保持正确坐姿', '适当进行颈部拉伸运动', '每工作1小时活动颈部5分钟'];
    }
    if (p <= 40) {
      return ['建议调整工作姿势，减少低头时间', '每天进行颈椎保健操', '可使用适合的颈椎枕', '如症状持续建议就医检查'];
    }
    if (p <= 60) {
      return ['建议尽快就医检查', '可能需要进行影像学检查（X光/MRI）', '在医生指导下进行康复训练', '避免长时间伏案工作'];
    }
    return ['请立即就医', '可能需要进一步影像学检查', '需要专业康复治疗', '日常活动需格外注意保护颈椎'];
  }

  void _next() {
    if (_currentPage < _questions.length - 1) {
      setState(() => _currentPage++);
    } else {
      setState(() => _showResult = true);
    }
  }

  void _prev() {
    if (_currentPage > 0) setState(() => _currentPage--);
  }

  void _reset() {
    setState(() { _currentPage = 0; _answers.clear(); _showResult = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NDI 颈椎功能障碍指数')),
      body: _showResult ? _buildResult(context) : _buildQuestion(context),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final theme = Theme.of(context);
    final q = _questions[_currentPage];
    final selected = _answers[_currentPage];

    return Column(
      children: [
        LinearProgressIndicator(value: (_currentPage + 1) / _questions.length, minHeight: 3),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('第 ${_currentPage + 1} / ${_questions.length} 题',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Text(q.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 20),
                ...List.generate(q.options.length, (i) {
                  final isSelected = selected == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _answers[_currentPage] = i),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? theme.colorScheme.primary : Colors.transparent, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                border: Border.all(color: isSelected ? theme.colorScheme.primary : AppColors.textSecondary, width: 1.5),
                              ),
                              child: Center(child: Text('$i', style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(q.options[i], style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_currentPage > 0) Expanded(child: OutlinedButton(onPressed: _prev, child: const Text('上一题'))),
              if (_currentPage > 0) const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: selected != null ? _next : null, child: Text(_currentPage == _questions.length - 1 ? '查看结果' : '下一题'))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(Icons.assessment, size: 72, color: _levelColor),
          const SizedBox(height: 16),
          Text(_levelText, style: theme.textTheme.headlineSmall?.copyWith(color: _levelColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('NDI评分：$_totalScore / 50 （${_percentage.toStringAsFixed(0)}%）', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          _ScoreGauge(score: _totalScore, maxScore: 50, color: _levelColor),
          const SizedBox(height: 24),
          _SuggestionList(suggestions: _suggestions, theme: theme),
          const SizedBox(height: 24),
          _ScoreBreakdown(questions: _questions, answers: _answers),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh), label: const Text('重新评估'))),
          const SizedBox(height: 8),
          Text('免责声明：本筛查仅供参考，不替代专业医学诊断。如有异常请及时就医。',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────

class _Q {
  final String title;
  final List<String> options;
  const _Q({required this.title, required this.options});
}

class _ScoreGauge extends StatelessWidget {
  final int score;
  final int maxScore;
  final Color color;
  const _ScoreGauge({required this.score, required this.maxScore, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('综合评分:', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 8),
          Text('$score / $maxScore', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final List<String> suggestions;
  final ThemeData theme;
  const _SuggestionList({required this.suggestions, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerLeft, child: Text('建议措施', style: theme.textTheme.titleMedium)),
        const SizedBox(height: 8),
        ...suggestions.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('• ', style: TextStyle(fontSize: 16)), Expanded(child: Text(s, style: theme.textTheme.bodyMedium))],
          ),
        )),
      ],
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  final List<_Q> questions;
  final Map<int, int> answers;
  const _ScoreBreakdown({required this.questions, required this.answers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerLeft, child: Text('各项得分', style: theme.textTheme.titleMedium)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: List.generate(questions.length, (i) {
              final ans = answers[i] ?? 0;
              return ListTile(
                dense: true,
                leading: CircleAvatar(radius: 14, backgroundColor: ans <= 1 ? AppColors.success : ans <= 3 ? AppColors.warning : AppColors.danger,
                  child: Text('$ans', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))),
                title: Text(questions[i].title, style: const TextStyle(fontSize: 14)),
                subtitle: Text(questions[i].options[ans], style: const TextStyle(fontSize: 12)),
              );
            }),
          ),
        ),
      ],
    );
  }
}
