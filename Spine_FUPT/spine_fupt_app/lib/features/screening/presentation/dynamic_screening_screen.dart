import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 动态筛查量表渲染器 — 根据 API 返回的 scale 数据自动渲染问卷
class DynamicScreeningScreen extends StatefulWidget {
  final Map<String, dynamic> scaleData;
  const DynamicScreeningScreen({super.key, required this.scaleData});
  @override
  State<DynamicScreeningScreen> createState() => _DynamicScreeningScreenState();
}

class _DynamicScreeningScreenState extends State<DynamicScreeningScreen> {
  late final String _scaleType;
  late final List<Map<String, dynamic>> _items;
  late final List<Map<String, dynamic>> _ranges;
  late final int _maxScore;

  // weighted paged state
  int _currentPage = 0;
  final Map<int, int> _weightedAnswers = {};

  // yes_no state
  final Map<int, bool> _yesNoAnswers = {};

  // slider state
  double _sliderValue = 0;

  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    _scaleType = widget.scaleData['scale_type'] as String? ?? 'weighted';
    _items = List<Map<String, dynamic>>.from(widget.scaleData['items'] ?? []);
    _ranges = List<Map<String, dynamic>>.from(widget.scaleData['result_ranges'] ?? []);
    _maxScore = widget.scaleData['max_score'] as int? ?? 0;
  }

  double get _computedScore {
    switch (_scaleType) {
      case 'weighted':
        double sum = 0;
        for (final entry in _weightedAnswers.entries) {
          final item = _items[entry.key];
          final options = List<Map<String, dynamic>>.from(item['options_json'] ?? []);
          if (entry.value < options.length) {
            sum += (options[entry.value]['weight'] as num?)?.toDouble() ?? entry.value.toDouble();
          }
        }
        return sum;
      case 'yes_no':
        return _yesNoAnswers.values.where((v) => v).length.toDouble();
      case 'slider':
        return _sliderValue;
      default:
        return 0;
    }
  }

  Map<String, dynamic>? get _matchedRange {
    final score = _computedScore;
    for (final r in _ranges) {
      final min = (r['min_score'] as num?)?.toDouble() ?? 0;
      final max = (r['max_score'] as num?)?.toDouble() ?? 0;
      if (score >= min && score <= max) return r;
    }
    return _ranges.isNotEmpty ? _ranges.last : null;
  }

  bool get _allAnswered {
    switch (_scaleType) {
      case 'weighted':
        return _weightedAnswers.length == _items.length;
      case 'yes_no':
        return _yesNoAnswers.length == _items.length;
      case 'slider':
        return true;
      default:
        return true;
    }
  }

  void _reset() {
    setState(() {
      _showResult = false;
      _currentPage = 0;
      _weightedAnswers.clear();
      _yesNoAnswers.clear();
      _sliderValue = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.scaleData['title'] ?? '量表评估')),
      body: _showResult ? _buildResult() : _buildQuestionnaire(),
    );
  }

  // ---------- Questionnaire body ----------

  Widget _buildQuestionnaire() {
    switch (_scaleType) {
      case 'weighted':
        return _buildWeightedPaged();
      case 'yes_no':
        return _buildYesNoList();
      case 'slider':
        return _buildSlider();
      default:
        return _buildWeightedPaged();
    }
  }

  // --- Weighted (paged, one question per page) ---

  Widget _buildWeightedPaged() {
    if (_items.isEmpty) return const Center(child: Text('暂无题目'));
    final item = _items[_currentPage];
    final options = List<Map<String, dynamic>>.from(item['options_json'] ?? []);
    final selected = _weightedAnswers[_currentPage];
    final theme = Theme.of(context);

    return Column(
      children: [
        // progress
        LinearProgressIndicator(
          value: (_currentPage + 1) / _items.length,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('第 ${_currentPage + 1} / ${_items.length} 题',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text(item['title'] ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if ((item['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item['description'], style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 20),
                ...List.generate(options.length, (oi) {
                  final opt = options[oi];
                  final isSelected = selected == oi;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _weightedAnswers[_currentPage] = oi),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                            width: isSelected ? 2 : 1,
                          ),
                          color: isSelected ? theme.colorScheme.primary.withOpacity(0.06) : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                              ),
                              child: Center(child: Text('$oi',
                                  style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(opt['label'] ?? opt['text'] ?? '', style: theme.textTheme.bodyMedium)),
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
        // bottom buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(child: OutlinedButton(onPressed: () => setState(() => _currentPage--), child: const Text('上一题'))),
                if (_currentPage > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: selected == null
                        ? null
                        : () {
                            if (_currentPage < _items.length - 1) {
                              setState(() => _currentPage++);
                            } else {
                              setState(() => _showResult = true);
                            }
                          },
                    child: Text(_currentPage < _items.length - 1 ? '下一题' : '查看结果'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Yes / No (scrollable list) ---

  Widget _buildYesNoList() {
    final theme = Theme.of(context);
    return Column(
      children: [
        // header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.scaleData['title'] ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if ((widget.scaleData['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(widget.scaleData['description'], style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              final answered = _yesNoAnswers.containsKey(i);
              final isYes = _yesNoAnswers[i] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ${item['title'] ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _yesNoAnswers[i] = true),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: (answered && isYes) ? AppColors.danger.withOpacity(0.1) : null,
                                side: BorderSide(color: (answered && isYes) ? AppColors.danger : theme.colorScheme.outlineVariant),
                              ),
                              child: Text('是', style: TextStyle(color: (answered && isYes) ? AppColors.danger : null)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _yesNoAnswers[i] = false),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: (answered && !isYes) ? AppColors.success.withOpacity(0.1) : null,
                                side: BorderSide(color: (answered && !isYes) ? AppColors.success : theme.colorScheme.outlineVariant),
                              ),
                              child: Text('否', style: TextStyle(color: (answered && !isYes) ? AppColors.success : null)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // submit button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _allAnswered ? () => setState(() => _showResult = true) : null,
                child: Text('提交评估 (已答 ${_yesNoAnswers.length} / ${_items.length})'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Slider ---

  Widget _buildSlider() {
    if (_items.isEmpty) return const Center(child: Text('暂无题目'));
    final item = _items.first;
    final theme = Theme.of(context);
    final sMin = (item['slider_min'] as num?)?.toDouble() ?? 0;
    final sMax = (item['slider_max'] as num?)?.toDouble() ?? 10;
    final sStep = (item['slider_step'] as num?)?.toDouble() ?? 0.1;
    final divisions = ((sMax - sMin) / sStep).round();
    final minLabel = item['slider_min_label'] ?? '无痛';
    final maxLabel = item['slider_max_label'] ?? '剧痛';

    // find matching range for current value
    final range = _matchedRange;
    final levelText = range?['level_text'] ?? '';
    final levelColor = _parseColor(range?['color'] as String? ?? '#34C759');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(item['title'] ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if ((item['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item['description'], style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 40),
          Text(_sliderValue.toStringAsFixed(1),
              style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: levelColor)),
          const SizedBox(height: 4),
          Text(levelText, style: theme.textTheme.titleSmall?.copyWith(color: levelColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: levelColor,
              thumbColor: levelColor,
              overlayColor: levelColor.withOpacity(0.15),
              inactiveTrackColor: levelColor.withOpacity(0.2),
            ),
            child: Slider(
              value: _sliderValue.clamp(sMin, sMax),
              min: sMin,
              max: sMax,
              divisions: divisions > 0 ? divisions : 100,
              onChanged: (v) => setState(() => _sliderValue = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${sMin.toInt()} $minLabel', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                Text('${sMax.toInt()} $maxLabel', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _showResult = true),
              child: const Text('查看结果'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Result page ----------

  Widget _buildResult() {
    final theme = Theme.of(context);
    final score = _computedScore;
    final range = _matchedRange;
    final levelText = range?['level_text'] ?? '暂无评级';
    final color = _parseColor(range?['color'] as String? ?? '#34C759');
    final description = range?['description'] ?? '';
    final suggestions = List<String>.from(range?['suggestions_json'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(
            _scaleType == 'slider' ? Icons.speed : (_scaleType == 'yes_no' ? Icons.fact_check : Icons.assessment),
            size: 56,
            color: color,
          ),
          const SizedBox(height: 12),
          Text(levelText, style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_scoreText(score), style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 20),
          // score gauge
          if (_scaleType != 'slider') _buildGauge(score, color, theme),
          if (_scaleType != 'slider') const SizedBox(height: 20),
          // suggestions
          if (suggestions.isNotEmpty) ...[
            Align(alignment: Alignment.centerLeft, child: Text('建议', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            ...suggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
          ],
          const SizedBox(height: 16),
          // per-question breakdown for weighted
          if (_scaleType == 'weighted') _buildBreakdown(theme),
          // yes-items summary for yes_no
          if (_scaleType == 'yes_no') _buildYesSummary(theme),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: _reset, child: const Text('重新评估')),
          ),
          const SizedBox(height: 12),
          Text('免责声明：本筛查仅供参考，不构成医学诊断。如有不适请及时就医。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _scoreText(double score) {
    if (_scaleType == 'slider') return '评分：${score.toStringAsFixed(1)}';
    if (_scaleType == 'yes_no') return '${score.toInt()} / ${_items.length} 项回答"是"';
    return '总分：${score.toInt()} / ${_maxScore > 0 ? _maxScore : ""}';
  }

  Widget _buildGauge(double score, Color color, ThemeData theme) {
    final maxVal = _scaleType == 'yes_no' ? _items.length.toDouble() : (_maxScore > 0 ? _maxScore.toDouble() : 1);
    final ratio = (score / maxVal).clamp(0.0, 1.0);
    return Container(
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: ratio,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: color),
        ),
      ),
    );
  }

  Widget _buildBreakdown(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('各项得分', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              final ans = _weightedAnswers[i];
              final options = List<Map<String, dynamic>>.from(item['options_json'] ?? []);
              double w = 0;
              String ansText = '未答';
              if (ans != null && ans < options.length) {
                w = (options[ans]['weight'] as num?)?.toDouble() ?? ans.toDouble();
                ansText = options[ans]['label'] ?? options[ans]['text'] ?? '';
              }
              final itemColor = w == 0 ? AppColors.success : (w <= 2 ? AppColors.warning : AppColors.danger);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, backgroundColor: itemColor.withOpacity(0.15), child: Text('${i + 1}', style: TextStyle(color: itemColor, fontSize: 12, fontWeight: FontWeight.w600))),
                title: Text(item['title'] ?? '', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(ansText, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('+${w.toInt()}', style: TextStyle(color: itemColor, fontWeight: FontWeight.w600, fontSize: 13)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildYesSummary(ThemeData theme) {
    final yesIndices = _yesNoAnswers.entries.where((e) => e.value).map((e) => e.key).toList();
    if (yesIndices.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您的风险因素', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...yesIndices.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_items[i]['title'] ?? '', style: theme.textTheme.bodySmall)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  static Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
