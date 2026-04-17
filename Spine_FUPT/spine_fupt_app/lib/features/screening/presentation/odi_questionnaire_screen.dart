import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// ODI 腰椎功能障碍指数问卷 (Oswestry Disability Index)
class OdiQuestionnaireScreen extends StatefulWidget {
  const OdiQuestionnaireScreen({super.key});
  @override
  State<OdiQuestionnaireScreen> createState() => _OdiQuestionnaireScreenState();
}

class _OdiQuestionnaireScreenState extends State<OdiQuestionnaireScreen> {
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
        '我能正常照顾自己但很疼',
        '照顾自己很疼且我需要缓慢小心',
        '我需要一些帮助但能完成大部分',
        '每天在大多数方面都需要帮助',
        '我无法自己穿衣，洗漱也很困难',
      ],
    ),
    _Q(
      title: '第三部分：提举重物',
      options: [
        '我能提起重物而不会额外疼痛',
        '我能提起重物但会引起额外疼痛',
        '疼痛使我无法从地面提起重物，但放在方便位置的可以（如桌上）',
        '疼痛使我无法提起重物，但轻到中等重量放在方便位置的可以',
        '我只能提很轻的东西',
        '我完全不能提或搬任何东西',
      ],
    ),
    _Q(
      title: '第四部分：行走',
      options: [
        '疼痛不影响行走任何距离',
        '疼痛使我无法行走超过1公里',
        '疼痛使我无法行走超过500米',
        '疼痛使我无法行走超过100米',
        '只能使用拐杖或助行器行走',
        '大多时候卧床，去卫生间需要爬行',
      ],
    ),
    _Q(
      title: '第五部分：坐',
      options: [
        '能坐在任何椅子上想坐多久就坐多久',
        '只能坐在特定的椅子上想坐多久就坐多久',
        '疼痛使我无法坐超过1小时',
        '疼痛使我无法坐超过半小时',
        '疼痛使我无法坐超过10分钟',
        '疼痛使我完全无法坐下',
      ],
    ),
    _Q(
      title: '第六部分：站立',
      options: [
        '能站立任意时长而不会额外疼痛',
        '能站立想站多久就站多久但会引起额外疼痛',
        '疼痛使我无法站立超过1小时',
        '疼痛使我无法站立超过30分钟',
        '疼痛使我无法站立超过10分钟',
        '疼痛使我完全无法站立',
      ],
    ),
    _Q(
      title: '第七部分：睡眠',
      options: [
        '睡眠从未受到疼痛干扰',
        '睡眠偶尔受到疼痛干扰',
        '因为疼痛睡眠不足6小时',
        '因为疼痛睡眠不足4小时',
        '因为疼痛睡眠不足2小时',
        '疼痛使我完全无法入睡',
      ],
    ),
    _Q(
      title: '第八部分：性生活（如适用）',
      options: [
        '性生活正常且无额外疼痛',
        '性生活正常但会引起一些额外疼痛',
        '性生活基本正常但非常疼',
        '性生活因疼痛严重受限',
        '性生活因疼痛几乎不可能',
        '疼痛使性生活完全不可能',
      ],
    ),
    _Q(
      title: '第九部分：社交生活',
      options: [
        '社交生活正常且不会引起额外疼痛',
        '社交生活正常但会增加疼痛程度',
        '疼痛对社交生活无明显影响，但限制了体力活动（如运动）',
        '疼痛限制了社交生活，我不经常外出',
        '疼痛使我只能待在家里',
        '疼痛使我没有社交生活',
      ],
    ),
    _Q(
      title: '第十部分：旅行',
      options: [
        '可以去任何地方旅行而不疼',
        '可以去任何地方旅行但会引起额外疼痛',
        '疼痛严重但能出行2小时以上',
        '疼痛限制我出行不能超过1小时',
        '疼痛限制我出行不能超过30分钟',
        '疼痛使我只能去看病',
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
    if (p <= 80) return '严重残疾';
    return '完全残疾/卧床';
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
      return ['腰椎功能基本正常', '注意日常搬重物姿势', '加强核心肌群锻炼', '避免久坐，每小时起身活动'];
    }
    if (p <= 40) {
      return ['建议到医院进行腰椎检查', '疼痛明显时可口服非处方止痛药', '学习正确的腰部保护姿势', '开始进行腰背肌功能锻炼（如飞燕式）'];
    }
    if (p <= 60) {
      return ['建议尽快就医', '可能需要腰椎MRI检查', '遵医嘱进行康复治疗', '避免弯腰搬重物', '考虑使用腰围保护'];
    }
    return ['请立即就医', '需要专业的影像学检查和治疗', '可能需要考虑手术治疗', '日常生活需要他人辅助'];
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
      appBar: AppBar(title: const Text('ODI 腰椎功能障碍指数')),
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
          Text('ODI评分：$_totalScore / 50 （${_percentage.toStringAsFixed(0)}%）', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: _levelColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('综合评分:', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 8),
              Text('$_totalScore / 50', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: _levelColor)),
            ]),
          ),
          const SizedBox(height: 24),
          Align(alignment: Alignment.centerLeft, child: Text('建议措施', style: theme.textTheme.titleMedium)),
          const SizedBox(height: 8),
          ..._suggestions.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(fontSize: 16)),
              Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
            ]),
          )),
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

class _Q {
  final String title;
  final List<String> options;
  const _Q({required this.title, required this.options});
}
