import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// VAS 疼痛评分 + RMQ 功能评估问卷
class BackpainQuestionnaireScreen extends StatefulWidget {
  const BackpainQuestionnaireScreen({super.key});
  @override
  State<BackpainQuestionnaireScreen> createState() => _BackpainQuestionnaireScreenState();
}

class _BackpainQuestionnaireScreenState extends State<BackpainQuestionnaireScreen>
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('腰背疼痛评估'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: 'VAS 疼痛评分'), Tab(text: 'RMQ 功能评估')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [_VasTab(), _RmqTab()],
      ),
    );
  }
}

// ─── VAS Tab ──────────────────────────────────────────────────────

class _VasTab extends StatefulWidget {
  const _VasTab();
  @override
  State<_VasTab> createState() => _VasTabState();
}

class _VasTabState extends State<_VasTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  double _vasScore = 0;
  bool _showResult = false;

  String get _painLevel {
    if (_vasScore == 0) return '无痛';
    if (_vasScore <= 3) return '轻度疼痛';
    if (_vasScore <= 6) return '中度疼痛';
    if (_vasScore <= 8) return '重度疼痛';
    return '剧烈疼痛';
  }

  Color get _painColor {
    if (_vasScore <= 3) return AppColors.success;
    if (_vasScore <= 6) return AppColors.warning;
    return AppColors.danger;
  }

  List<String> get _suggestions {
    if (_vasScore <= 3) {
      return ['轻度疼痛通常无需特殊处理', '注意日常姿势保持正确', '适当进行腰背肌锻炼', '如疼痛反复出现建议就医'];
    }
    if (_vasScore <= 6) {
      return ['建议就医查明疼痛原因', '可在医生指导下口服止痛药物', '避免久坐和弯腰提重物', '热敷或理疗可缓解症状', '学习腰部保护动作'];
    }
    return ['请尽快就医', '可能需要影像学检查', '需要专业疼痛管理', '严格避免加重疼痛的活动', '必要时卧床休息'];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_showResult) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Icon(Icons.speed, size: 72, color: _painColor),
            const SizedBox(height: 16),
            Text(_painLevel, style: theme.textTheme.headlineSmall?.copyWith(color: _painColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('VAS评分：${_vasScore.toStringAsFixed(1)} / 10', style: theme.textTheme.bodyLarge),
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
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => setState(() => _showResult = false), icon: const Icon(Icons.refresh), label: const Text('重新评估'))),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text('请用手指在下方滑块上选择您目前的疼痛程度', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('0 = 完全不痛，10 = 能想象到的最痛', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 40),
          // VAS slider
          Center(
            child: Text(
              _vasScore.toStringAsFixed(1),
              style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: _painColor),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(_painLevel, style: theme.textTheme.titleMedium?.copyWith(color: _painColor))),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0\n无痛', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success)),
              Text('5\n中度', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
              Text('10\n剧痛', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _painColor,
              thumbColor: _painColor,
              overlayColor: _painColor.withOpacity(0.2),
              inactiveTrackColor: _painColor.withOpacity(0.15),
            ),
            child: Slider(
              value: _vasScore,
              min: 0,
              max: 10,
              divisions: 100,
              onChanged: (v) => setState(() => _vasScore = v),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _showResult = true),
              child: const Text('查看结果'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── RMQ Tab ──────────────────────────────────────────────────────

class _RmqTab extends StatefulWidget {
  const _RmqTab();
  @override
  State<_RmqTab> createState() => _RmqTabState();
}

class _RmqTabState extends State<_RmqTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Map<int, bool> _answers = {};
  bool _showResult = false;

  static const _statements = <String>[
    '因为腰背痛,我大部分时间都待在家里',
    '我经常变换姿势来让腰背舒服些',
    '因为腰背痛,我走路比平时慢',
    '因为腰背痛,我无法做一些我通常能做的家务',
    '因为腰背痛,我上楼梯时需要扶扶手',
    '因为腰背痛,我躺下休息比平时更频繁',
    '因为腰背痛,我需要扶着东西才能从坐椅上站起来',
    '因为腰背痛,我试图让别人来帮我做事',
    '因为腰背痛,我穿衣服比平时慢',
    '因为腰背痛,我只能站立很短时间',
    '因为腰背痛,我弯腰或跪下时小心翼翼',
    '因为腰背痛,我觉得很难从椅子上站起来',
    '我的腰背几乎一直都在痛',
    '因为腰背痛,我翻身有困难',
    '因为腰背痛,我没有什么食欲',
    '因为腰背痛,我穿袜子（或者长筒袜）有困难',
    '因为腰背痛,我只能走很短的距离',
    '我的睡眠不如以前好（因为腰背痛）',
    '因为腰背痛,我穿衣需要别人帮忙',
    '因为腰背痛,我大部分时间都坐着',
    '因为腰背痛,我避免在家里做繁重的工作',
    '因为腰背痛,我比平时更容易发脾气',
    '因为腰背痛,我上楼梯比平时慢',
    '因为腰背痛,我大部分时间都躺在床上',
  ];

  int get _totalScore => _answers.values.where((v) => v).length;

  String get _levelText {
    final s = _totalScore;
    if (s <= 6) return '轻度功能障碍';
    if (s <= 12) return '中度功能障碍';
    if (s <= 18) return '重度功能障碍';
    return '严重功能障碍';
  }

  Color get _levelColor {
    final s = _totalScore;
    if (s <= 6) return AppColors.success;
    if (s <= 12) return AppColors.warning;
    if (s <= 18) return const Color(0xFFFF9500);
    return AppColors.danger;
  }

  List<String> get _suggestions {
    final s = _totalScore;
    if (s <= 6) return ['日常功能影响较小', '继续保持适量运动', '注意正确坐姿和站姿'];
    if (s <= 12) return ['建议就医查明腰背痛原因', '在物理治疗师指导下进行康复训练', '避免久坐和重体力劳动'];
    return ['请尽快去骨科或疼痛科就诊', '可能需要影像学检查和专业治疗', '日常活动中注意腰部保护', '必要时使用腰围辅助'];
  }

  void _reset() {
    setState(() { _answers.clear(); _showResult = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_showResult) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Icon(Icons.assessment, size: 72, color: _levelColor),
            const SizedBox(height: 16),
            Text(_levelText, style: theme.textTheme.headlineSmall?.copyWith(color: _levelColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('RMQ评分：$_totalScore / 24', style: theme.textTheme.bodyLarge),
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
            Text('免责声明：本筛查仅供参考，不替代专业医学诊断。',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('以下描述是否符合您过去24小时的情况？请逐条勾选。',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _statements.length,
            itemBuilder: (ctx, i) {
              final checked = _answers[i] ?? false;
              return CheckboxListTile(
                value: checked,
                onChanged: (v) => setState(() => _answers[i] = v ?? false),
                title: Text(_statements[i], style: theme.textTheme.bodyMedium),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _showResult = true),
              child: Text('查看结果（已选 $_totalScore / 24）'),
            ),
          ),
        ),
      ],
    );
  }
}
