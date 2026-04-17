import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 脊柱疾病自测筛查页面
/// 包含问卷评估 + 图文体测引导两部分
class SpineScreeningScreen extends StatefulWidget {
  const SpineScreeningScreen({super.key});
  @override
  State<SpineScreeningScreen> createState() => _SpineScreeningScreenState();
}

class _SpineScreeningScreenState extends State<SpineScreeningScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('脊柱健康筛查'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '问卷自评'),
            Tab(text: '体测引导'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _QuestionnaireTab(),
          _PhysicalGuideTab(),
        ],
      ),
    );
  }
}

// ─── 问卷评估 Tab ─────────────────────────────────────────────────

class _QuestionnaireTab extends StatefulWidget {
  const _QuestionnaireTab();
  @override
  State<_QuestionnaireTab> createState() => _QuestionnaireTabState();
}

class _QuestionnaireTabState extends State<_QuestionnaireTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _currentPage = 0;
  final Map<int, int> _answers = {};
  bool _showResult = false;

  static const _questions = <_ScreeningQuestion>[
    _ScreeningQuestion(
      title: '双肩是否等高？',
      description: '站直后，请他人观察或对着镜子检查双肩高度。',
      icon: Icons.accessibility_new,
      options: ['完全等高', '轻微不等高（<1cm）', '明显不等高（≥1cm）'],
      weights: [0, 1, 3],
    ),
    _ScreeningQuestion(
      title: '肩胛骨是否对称？',
      description: '弯腰前屈时观察背部，看肩胛骨是否一侧突出。',
      icon: Icons.compare_arrows,
      options: ['对称、未突出', '轻微不对称', '一侧明显突出'],
      weights: [0, 1, 3],
    ),
    _ScreeningQuestion(
      title: '腰线（腰部褶皱）是否对称？',
      description: '自然站立，双手下垂，观察腰部两侧褶皱是否一致。',
      icon: Icons.straighten,
      options: ['对称', '轻微不对称', '明显不对称'],
      weights: [0, 1, 3],
    ),
    _ScreeningQuestion(
      title: 'Adams 前屈测试',
      description: '双脚并拢，弯腰前屈90°，双手自然下垂。请他人从背后观察脊柱两侧是否有隆起。',
      icon: Icons.airline_seat_flat,
      options: ['两侧平坦对称', '一侧轻微隆起', '一侧明显隆起（隆起>1cm）'],
      weights: [0, 2, 4],
    ),
    _ScreeningQuestion(
      title: '骨盆是否水平？',
      description: '站直后，将双手放在骨盆（髂骨嵴）两侧，比较高度。',
      icon: Icons.balance,
      options: ['水平', '轻微倾斜', '明显倾斜'],
      weights: [0, 1, 3],
    ),
    _ScreeningQuestion(
      title: '是否有背部或腰部疼痛？',
      description: '近3个月内是否出现持续或反复的背部、腰部疼痛？',
      icon: Icons.healing,
      options: ['无疼痛', '偶尔轻微疼痛', '经常疼痛或持续疼痛'],
      weights: [0, 1, 2],
    ),
    _ScreeningQuestion(
      title: '头部是否居中？',
      description: '站直面向镜子，观察头部是否偏向一侧。',
      icon: Icons.face,
      options: ['居中', '轻微偏一侧', '明显偏一侧'],
      weights: [0, 1, 2],
    ),
    _ScreeningQuestion(
      title: '是否有脊柱疾病家族史？',
      description: '直系亲属中是否有人被诊断过脊柱侧弯、驼背等脊柱疾病？',
      icon: Icons.family_restroom,
      options: ['没有', '不确定', '有'],
      weights: [0, 1, 2],
    ),
  ];

  int get _totalScore {
    int s = 0;
    for (final e in _answers.entries) {
      s += _questions[e.key].weights[e.value];
    }
    return s;
  }

  _RiskLevel get _riskLevel {
    final s = _totalScore;
    if (s <= 2) return _RiskLevel.low;
    if (s <= 7) return _RiskLevel.medium;
    return _RiskLevel.high;
  }

  void _next() {
    if (_currentPage < _questions.length - 1) {
      setState(() => _currentPage++);
    } else {
      setState(() => _showResult = true);
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    }
  }

  void _reset() {
    setState(() {
      _currentPage = 0;
      _answers.clear();
      _showResult = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_showResult) return _buildResult(context);
    return _buildQuestion(context);
  }

  Widget _buildQuestion(BuildContext context) {
    final theme = Theme.of(context);
    final q = _questions[_currentPage];
    final selected = _answers[_currentPage];

    return Column(
      children: [
        // Progress
        LinearProgressIndicator(
          value: (_currentPage + 1) / _questions.length,
          minHeight: 3,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question number
                Text(
                  '第 ${_currentPage + 1} / ${_questions.length} 题',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                // Icon + Title
                Row(
                  children: [
                    Icon(q.icon, size: 28, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(q.title, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(q.description, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                // Options
                ...List.generate(q.options.length, (i) {
                  final isSelected = selected == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _answers[_currentPage] = i),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withOpacity(0.08)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isSelected ? theme.colorScheme.primary : AppColors.textSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(q.options[i], style: theme.textTheme.bodyLarge)),
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
        // Nav buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_currentPage > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _prev,
                    child: const Text('上一题'),
                  ),
                ),
              if (_currentPage > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: selected != null ? _next : null,
                  child: Text(_currentPage == _questions.length - 1 ? '查看结果' : '下一题'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final level = _riskLevel;
    final score = _totalScore;

    Color color;
    IconData icon;
    String title;
    String desc;
    List<String> suggestions;

    switch (level) {
      case _RiskLevel.low:
        color = AppColors.success;
        icon = Icons.check_circle;
        title = '风险较低';
        desc = '您的脊柱自评结果未发现明显异常迹象，当前脊柱健康状况良好。';
        suggestions = [
          '保持良好坐姿和站姿',
          '每天适量运动（如游泳、瑜伽）',
          '每年进行一次体检，关注脊柱健康',
          '青少年建议每6个月筛查一次',
        ];
      case _RiskLevel.medium:
        color = AppColors.warning;
        icon = Icons.warning_amber;
        title = '存在一定风险';
        desc = '您的脊柱自评发现部分异常迹象（得分 $score/22），建议进一步检查确认。';
        suggestions = [
          '建议前往医院拍摄站立位脊柱全长X光片',
          '可上传影像至本平台获取AI辅助分析',
          '避免长时间弯腰或单侧负重',
          '加强核心肌群锻炼',
          '如有疼痛建议尽早就诊',
        ];
      case _RiskLevel.high:
        color = AppColors.danger;
        icon = Icons.error;
        title = '风险较高';
        desc = '您的脊柱自评发现多处异常迹象（得分 $score/22），强烈建议尽快就医检查。';
        suggestions = [
          '尽快前往骨科或脊柱外科就诊',
          '拍摄站立位脊柱全长正侧位X光片',
          '不要自行尝试矫正，以免加重',
          '可先上传影像获取AI辅助分析参考',
          '遵医嘱决定是否佩戴矫形支具或手术治疗',
        ];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(desc, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          // Score gauge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('综合评分:', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 8),
                Text('$score / 22', style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Suggestions
          Align(
            alignment: Alignment.centerLeft,
            child: Text('建议措施', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          ...suggestions.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
              ],
            ),
          )),
          const SizedBox(height: 24),
          // Detail breakdown
          Align(
            alignment: Alignment.centerLeft,
            child: Text('各项得分', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: List.generate(_questions.length, (i) {
                final q = _questions[i];
                final ans = _answers[i] ?? 0;
                final w = q.weights[ans];
                return ListTile(
                  dense: true,
                  leading: Icon(q.icon, size: 20, color: w == 0 ? AppColors.success : w <= 1 ? AppColors.warning : AppColors.danger),
                  title: Text(q.title, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(q.options[ans], style: const TextStyle(fontSize: 12)),
                  trailing: Text('+$w', style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: w == 0 ? AppColors.success : w <= 1 ? AppColors.warning : AppColors.danger,
                  )),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('重新评估'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '免责声明：本筛查仅供参考，不替代专业医学诊断。如有异常请及时就医。',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── 体测引导 Tab ─────────────────────────────────────────────────

class _PhysicalGuideTab extends StatefulWidget {
  const _PhysicalGuideTab();
  @override
  State<_PhysicalGuideTab> createState() => _PhysicalGuideTabState();
}

class _PhysicalGuideTabState extends State<_PhysicalGuideTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _currentStep = 0;

  static const _steps = <_GuideStep>[
    _GuideStep(
      title: '站立姿势检查',
      icon: Icons.accessibility_new,
      instructions: [
        '自然站立，双脚并拢',
        '请他人或对着全身镜从正面和背面观察',
        '注意双肩是否等高',
        '观察腰部两侧褶皱是否对称',
        '头部是否正对前方',
      ],
      checkpoints: ['双肩等高', '腰线对称', '头部居中', '身体不偏一侧'],
      abnormalSigns: '若双肩明显不等高、身体明显向一侧倾斜、或腰线不对称，提示可能存在脊柱侧弯。',
    ),
    _GuideStep(
      title: 'Adams 前屈测试',
      icon: Icons.airline_seat_flat,
      instructions: [
        '双脚并拢，自然站立',
        '缓慢弯腰前屈约90°',
        '双臂自然下垂',
        '请他人从背后水平视线观察脊柱两侧',
        '重点关注胸椎和腰椎区域',
      ],
      checkpoints: ['背部两侧平坦对称', '无一侧隆起', '脊柱中线直'],
      abnormalSigns: '若弯腰后一侧背部明显比另一侧高（旋转隆起），是脊柱侧弯的重要体征。隆起越明显，可能严重程度越高。',
    ),
    _GuideStep(
      title: '肩胛骨检查',
      icon: Icons.compare_arrows,
      instructions: [
        '穿贴身或裸露上身',
        '自然站立，双手放身体两侧',
        '从背面观察两侧肩胛骨位置',
        '弯腰前屈时重点观察肩胛骨区域',
      ],
      checkpoints: ['两侧肩胛骨位置对称', '肩胛骨未翘起', '肩胛下角等高'],
      abnormalSigns: '若一侧肩胛骨明显突出（翼状肩胛）、或一侧肩胛骨比另一侧高，可能提示胸椎侧弯或肌肉不平衡。',
    ),
    _GuideStep(
      title: '骨盆水平检查',
      icon: Icons.balance,
      instructions: [
        '自然站立，脱鞋',
        '将双手拇指放在两侧骨盆最高点（髂骨嵴）',
        '从正面或背面观察双手是否在同一水平线',
        '也可观察皮带线是否水平',
      ],
      checkpoints: ['骨盆两侧等高', '站立时重心均匀'],
      abnormalSigns: '若骨盆明显倾斜（一高一低），可能提示下肢不等长或腰椎侧弯。',
    ),
    _GuideStep(
      title: '颈椎活动度检查',
      icon: Icons.screen_rotation,
      instructions: [
        '端坐或站立，目视前方',
        '缓慢左右转头，注意活动范围是否对称',
        '缓慢低头和仰头，感受是否疼痛',
        '缓慢向左右侧屈颈部',
        '注意各方向活动时有无疼痛、弹响',
      ],
      checkpoints: ['转头幅度左右对称（约60-80°）', '低头仰头无明显受限', '侧屈对称', '活动无疼痛'],
      abnormalSigns: '若转头、低头受限，或活动时出现疼痛、手臂放射性麻木，可能提示颈椎疾病。长期低头伏案者尤需注意。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final step = _steps[_currentStep];

    return Column(
      children: [
        // Step indicator
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_steps.length, (i) {
              final isActive = i == _currentStep;
              final isDone = i < _currentStep;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 28 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary
                      : isDone
                          ? theme.colorScheme.primary.withOpacity(0.4)
                          : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(step.icon, size: 28, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('第 ${_currentStep + 1} 步', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                          Text(step.title, style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Instructions
                Text('操作步骤', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 8),
                ...step.instructions.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text('${e.key + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),

                // Checkpoints
                Text('正常标准', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.success)),
                const SizedBox(height: 8),
                ...step.checkpoints.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),

                // Abnormal signs
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                          const SizedBox(width: 6),
                          Text('异常提示', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(step.abnormalSigns, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        // Nav buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _currentStep--),
                    child: const Text('上一步'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _currentStep < _steps.length - 1
                      ? () => setState(() => _currentStep++)
                      : null,
                  child: Text(_currentStep < _steps.length - 1 ? '下一步' : '全部完成'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────

enum _RiskLevel { low, medium, high }

class _ScreeningQuestion {
  final String title;
  final String description;
  final IconData icon;
  final List<String> options;
  final List<int> weights;

  const _ScreeningQuestion({
    required this.title,
    required this.description,
    required this.icon,
    required this.options,
    required this.weights,
  });
}

class _GuideStep {
  final String title;
  final IconData icon;
  final List<String> instructions;
  final List<String> checkpoints;
  final String abnormalSigns;

  const _GuideStep({
    required this.title,
    required this.icon,
    required this.instructions,
    required this.checkpoints,
    required this.abnormalSigns,
  });
}
