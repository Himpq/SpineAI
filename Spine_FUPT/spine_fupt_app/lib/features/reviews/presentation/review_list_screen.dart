import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';
import '../../models.dart';

class ReviewListScreen extends ConsumerStatefulWidget {
  const ReviewListScreen({super.key});
  @override
  ConsumerState<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends ConsumerState<ReviewListScreen> {
  String _filter = 'all';
  bool _refreshing = false;

  Future<void> _doRefresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.refresh(reviewListProvider.future);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刷新')));
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final reviews = ref.watch(reviewListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('复核中心'),
        actions: [
          _refreshing
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _doRefresh),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(label: '全部', value: 'all', selected: _filter, onSelected: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: '待复核', value: 'pending_review', selected: _filter, onSelected: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: '已复核', value: 'reviewed', selected: _filter, onSelected: (v) => setState(() => _filter = v)),
                const SizedBox(width: 8),
                _FilterChip(label: '推理失败', value: 'inference_failed', selected: _filter, onSelected: (v) => setState(() => _filter = v)),
              ],
            ),
          ),
          Expanded(
            child: reviews.when(
              loading: () => const ShimmerReviewList(),
              error: (e, _) => Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ApiClient.friendlyError(e)),
                  const SizedBox(height: 8),
                  _refreshing
                      ? const CircularProgressIndicator()
                      : FilledButton(onPressed: _doRefresh, child: const Text('重试')),
                ],
              )),
              data: (list) {
                final filtered = _filter == 'all' ? list : list.where((e) => e.status == _filter).toList();
                if (filtered.isEmpty) {
                  return Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.biotech_outlined, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      const Text('暂无复核记录'),
                    ],
                  ));
                }
                return RefreshIndicator(
                  onRefresh: _doRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ReviewTile(exam: filtered[i], baseUrl: ref.read(serverUrlProvider)),
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
  final ValueChanged<String> onSelected;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ExamModel exam;
  final String baseUrl;
  const _ReviewTile({required this.exam, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color statusColor;
    String statusLabel;
    switch (exam.status) {
      case 'reviewed':
        statusColor = AppColors.success;
        statusLabel = '已复核';
        break;
      case 'inference_failed':
        statusColor = AppColors.danger;
        statusLabel = '失败';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = '待复核';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: exam.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _getFullUrl(exam.imageUrl!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white54),
                  ),
                )
              : const Icon(Icons.image, color: Colors.white54),
        ),
        title: Text(exam.patientName ?? '患者#${exam.patientId}'),
        subtitle: Row(
          children: [
            if (exam.spineClassText != null) Text('${exam.spineClassText} ', style: const TextStyle(fontSize: 12)),
            if (exam.cobbAngle != null) Text('Cobb: ${exam.cobbAngle!.toStringAsFixed(1)}° ', style: const TextStyle(fontSize: 12)),
            Text(exam.createdAt?.substring(0, 10) ?? '', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
        ),
        onTap: () => context.push('/doctor/reviews/${exam.id}'),
      ),
    );
  }

  String _getFullUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
