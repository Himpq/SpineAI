import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// IOF 骨质疏松一分钟风险测试 (IOF One-Minute Risk Test)
class IofQuestionnaireScreen extends StatefulWidget {
  const IofQuestionnaireScreen({super.key});
  @override
  State<IofQuestionnaireScreen> createState() => _IofQuestionnaireScreenState();
}

class _IofQuestionnaireScreenState extends State<IofQuestionnaireScreen> {
  final Map<int, bool> _answers = {};
  bool _showResult = false;

  static const _questions = <String>[
    '您的父母是否有过轻微碰撞或跌倒就发生髋骨（股骨颈）骨折的情况？',
    '您本人是否有过轻微碰撞或跌倒就发生骨折的经历？',
    '您是否曾连续使用可的松、强的松等糖皮质激素类药物超过3个月？',
    '您的身高是否缩短了3厘米以上？',
    '您是否经常过量饮酒（每天饮用量超过啤酒500ml或白酒50ml）？',
    '您每天吸烟是否超过20支？',
    '您是否经常患腹泻？（由乳糜泻或克罗恩病等引起）',
    '女性：您是否在45岁之前就已经绝经？',
    '女性：除了怀孕、绝经或子宫切除外，您是否有过连续12个月以上没有月经的情况？',
    '男性：您是否曾患有阳痿、缺乏性欲或其他与低睾酮水平相关的症状？',
    '您是否每天从事少于30分钟的体力活动（如家务、园艺、散步、跑步等）？',
    '您目前的年龄是否超过60岁？',
    '您是否在近期有过明显的体重下降（超过5公斤）且未刻意减肥？',
  ];

  int get _yesCount => _answers.values.where((v) => v).length;

  bool get _isHighRisk => _yesCount >= 1;

  Color get _resultColor => _yesCount == 0 ? AppColors.success : _yesCount <= 2 ? AppColors.warning : AppColors.danger;

  String get _resultTitle {
    if (_yesCount == 0) return '风险较低';
    if (_yesCount <= 2) return '存在风险因素';
    return '高风险';
  }

  List<String> get _suggestions {
    if (_yesCount == 0) {
      return [
        '未发现明显骨质疏松风险因素',
        '建议保持适量运动和均衡饮食',
        '每天保证足够的钙质和维生素D摄入',
        '60岁以后建议定期进行骨密度检测',
      ];
    }
    if (_yesCount <= 2) {
      return [
        '存在${_yesCount}项骨质疏松风险因素',
        '建议进行骨密度检测（DXA扫描）',
        '增加钙质摄入（每日800-1200mg）',
        '补充维生素D（每日400-800IU）',
        '加强负重运动如快走、跑步、跳绳',
        '40岁以上建议每1-2年检测一次骨密度',
      ];
    }
    return [
      '存在${_yesCount}项骨质疏松风险因素，风险较高',
      '请尽快到医院进行骨密度检测',
      '咨询内分泌科或骨科医生',
      '可能需要药物干预治疗',
      '注意防摔措施，避免骨折风险',
      '保证充足的钙和维生素D摄入',
    ];
  }

  void _reset() {
    setState(() { _answers.clear(); _showResult = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IOF 骨质疏松风险测试')),
      body: _showResult ? _buildResult(context) : _buildQuestions(context),
    );
  }

  Widget _buildQuestions(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('国际骨质疏松基金会一分钟风险测试',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('请根据您的实际情况回答以下问题，只要有一项回答"是"就建议进行骨密度检查。',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _questions.length,
            itemBuilder: (ctx, i) {
              final q = _questions[i];
              final ans = _answers[i];
              // Skip gender-specific questions (show hint)
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. $q', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _answers[i] = true),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: ans == true ? AppColors.danger.withOpacity(0.1) : null,
                                  side: BorderSide(color: ans == true ? AppColors.danger : theme.colorScheme.outline),
                                  foregroundColor: ans == true ? AppColors.danger : null,
                                ),
                                child: const Text('是'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _answers[i] = false),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: ans == false ? AppColors.success.withOpacity(0.1) : null,
                                  side: BorderSide(color: ans == false ? AppColors.success : theme.colorScheme.outline),
                                  foregroundColor: ans == false ? AppColors.success : null,
                                ),
                                child: const Text('否'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _answers.length == _questions.length
                  ? () => setState(() => _showResult = true)
                  : null,
              child: Text('查看结果（已答 ${_answers.length} / ${_questions.length}）'),
            ),
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
          Icon(
            _yesCount == 0 ? Icons.check_circle : Icons.warning_amber,
            size: 72,
            color: _resultColor,
          ),
          const SizedBox(height: 16),
          Text(_resultTitle, style: theme.textTheme.headlineSmall?.copyWith(color: _resultColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${_questions.length}项问题中有 $_yesCount 项回答"是"', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: _resultColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('风险因素:', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 8),
              Text('$_yesCount / ${_questions.length}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: _resultColor)),
            ]),
          ),
          const SizedBox(height: 24),
          // Show which questions were answered "yes"
          if (_yesCount > 0) ...[
            Align(alignment: Alignment.centerLeft, child: Text('您的风险因素', style: theme.textTheme.titleMedium)),
            const SizedBox(height: 8),
            ..._answers.entries.where((e) => e.value).map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_questions[e.key], style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
            const SizedBox(height: 16),
          ],
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
