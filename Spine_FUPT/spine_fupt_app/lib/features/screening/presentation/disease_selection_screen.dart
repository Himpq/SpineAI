import 'package:flutter/material.dart';
import '../data/screening_scale_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'dynamic_screening_screen.dart';

/// 疾病筛查选择页面 — 从后端API加载量表列表，支持离线内置默认
class DiseaseSelectionScreen extends StatefulWidget {
  const DiseaseSelectionScreen({super.key});
  @override
  State<DiseaseSelectionScreen> createState() => _DiseaseSelectionScreenState();
}

class _DiseaseSelectionScreenState extends State<DiseaseSelectionScreen> {
  List<Map<String, dynamic>> _scales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _scales = await ScreeningScaleRepository().getPublicScales();
    } catch (_) {
      // Fallback: empty list, user can retry
      _scales = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  static Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  static IconData _mapIcon(String? name) {
    const map = <String, IconData>{
      'accessibility_new': Icons.accessibility_new,
      'face': Icons.face,
      'airline_seat_recline_normal': Icons.airline_seat_recline_normal,
      'healing': Icons.healing,
      'elderly': Icons.elderly,
    };
    return map[name] ?? Icons.quiz;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('脊柱健康筛查')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scales.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text('暂无筛查量表'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _scales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final s = _scales[i];
                      final color = _parseColor(s['color'] as String? ?? '#3478F6');
                      return _DiseaseCard(
                        title: s['title'] ?? '',
                        subtitle: s['subtitle'] ?? '',
                        description: s['description'] ?? '',
                        icon: _mapIcon(s['icon'] as String?),
                        color: color,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DynamicScreeningScreen(scaleData: s),
                          ));
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _DiseaseCard({required this.title, required this.subtitle, required this.description, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            )),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}
