import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';
import '../../models.dart';

class ReviewDetailScreen extends ConsumerStatefulWidget {
  final int examId;
  const ReviewDetailScreen({super.key, required this.examId});
  @override
  ConsumerState<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends ConsumerState<ReviewDetailScreen> {
  ExamModel? _exam;
  bool _loading = true;
  bool _showAi = true;
  final _noteCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(reviewRepoProvider).getReviewDetail(widget.examId);
      setState(() {
        _exam = data;
        _noteCtrl.text = data.reviewNote ?? '';
        _comments = data.comments ?? [];
        _loading = false;
        _error = null;
      });
      // Subscribe to comment channel
      if (data.commentChannel != null) {
        ref.read(wsClientProvider).subscribe(data.commentChannel!);
        ref.read(wsClientProvider).on('case_comment', (payload) {
          if (!mounted) return;
          final comment = payload['comment'] as Map<String, dynamic>? ?? payload;
          // Deduplicate: skip if already added locally
          final cid = comment['id'];
          if (cid != null && _comments.any((c) => c['id'] == cid)) return;
          setState(() => _comments.add(comment));
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  @override
  void dispose() {
    if (_exam?.commentChannel != null) {
      ref.read(wsClientProvider).unsubscribe(_exam!.commentChannel!);
    }
    _noteCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_exam == null) return Scaffold(appBar: AppBar(), body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error ?? '加载失败'),
        const SizedBox(height: 8),
        FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('重试')),
      ],
    )));
    final exam = _exam!;
    final baseUrl = ref.read(serverUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(exam.patientName ?? '复核详情'),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: () => _showShareSheet(context, exam)),
        ],
      ),
      body: Column(
        children: [
          // Image viewer section
          Expanded(
            flex: 55,
            child: Container(
              color: Colors.black,
              child: _buildImageViewer(exam, baseUrl),
            ),
          ),
          // AI/Raw toggle (outside Stack to avoid PhotoView gesture conflicts)
          if (exam.hasAiImage)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('AI推理图')),
                  ButtonSegment(value: false, label: Text('原始图')),
                ],
                selected: {_showAi},
                onSelectionChanged: (v) => setState(() => _showAi = v.first),
              ),
            ),
          // Info panel section
          Expanded(
            flex: 45,
            child: _buildInfoPanel(exam, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewer(ExamModel exam, String baseUrl) {
    String? url;
    if (_showAi && exam.inferenceImageUrl != null) {
      url = exam.inferenceImageUrl!;
    } else if (exam.rawImageUrl != null && exam.rawImageUrl!.isNotEmpty) {
      url = exam.rawImageUrl!;
    } else if (exam.imageUrl != null) {
      url = exam.imageUrl!;
    }
    if (url == null) return const Center(child: Icon(Icons.image_not_supported, color: Colors.white38, size: 64));
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';

    return PhotoView(
      key: ValueKey(fullUrl),
      imageProvider: NetworkImage(fullUrl),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained * 0.8,
      maxScale: PhotoViewComputedScale.covered * 6.0,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, e) => Center(child: CircularProgressIndicator(
        value: e?.expectedTotalBytes != null ? e!.cumulativeBytesLoaded / e.expectedTotalBytes! : null,
        color: Colors.white54,
      )),
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 64)),
    );
  }

  Widget _buildInfoPanel(ExamModel exam, ThemeData theme) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(tabs: const [
            Tab(text: '推理结果'),
            Tab(text: '复核'),
            Tab(text: '评论'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _buildInferenceTab(exam, theme),
                _buildReviewTab(exam, theme),
                _buildCommentsTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInferenceTab(ExamModel exam, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (exam.spineClassText != null)
          _InfoRow('分类', exam.spineClassText!),
        if (exam.spineClassConfidence != null)
          _InfoRow('置信度', '${(exam.spineClassConfidence! * 100).toStringAsFixed(1)}%'),
        if (exam.cobbAngle != null)
          _InfoRow('Cobb角', '${exam.cobbAngle!.toStringAsFixed(1)}°'),
        if (exam.curveValue != null)
          _InfoRow('曲度值', exam.curveValue!.toStringAsFixed(2)),
        if (exam.severityLabel != null)
          _InfoRow('严重程度', exam.severityLabel!),
        if (exam.improvementValue != null)
          _InfoRow('改善值', '${exam.improvementValue! > 0 ? "+" : ""}${exam.improvementValue!.toStringAsFixed(1)}°'),
        if (exam.cervicalMetric != null) ...[
          const Divider(height: 24),
          Text('颈椎指标', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (exam.cervicalMetric!['left_ratio'] != null)
            _InfoRow('左侧比率', exam.cervicalMetric!['left_ratio'].toString()),
          if (exam.cervicalMetric!['right_ratio'] != null)
            _InfoRow('右侧比率', exam.cervicalMetric!['right_ratio'].toString()),
          if (exam.cervicalMetric!['assessment'] != null)
            _InfoRow('评估', exam.cervicalMetric!['assessment'].toString()),
        ],
        if (exam.isFailed) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 8),
              const Expanded(child: Text('推理失败，请检查影像质量后重新上传', style: TextStyle(color: AppColors.danger))),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _buildReviewTab(ExamModel exam, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('状态: ', style: theme.textTheme.titleSmall),
            Chip(
              label: Text(exam.isReviewed ? '已复核' : '待复核'),
              backgroundColor: exam.isReviewed ? AppColors.successLight : AppColors.warningLight,
            ),
          ],
        ),
        if (exam.reviewedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('复核时间: ${exam.reviewedAt}', style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '复核备注',
            border: OutlineInputBorder(),
            hintText: '输入复核备注...',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submitting ? null : () => _submitReview(exam),
          icon: Icon(_submitting ? Icons.hourglass_empty : Icons.check_circle),
          label: Text(_submitting ? '提交中...' : '提交复核'),
        ),
        if (exam.isReviewed) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _submitting ? null : () => _undoReview(exam),
            icon: const Icon(Icons.undo),
            label: const Text('撤销复核'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
          ),
        ],
      ],
    );
  }

  Widget _buildCommentsTab(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: _comments.isEmpty
              ? const Center(child: Text('暂无评论'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c = _comments[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(radius: 16, child: Text((c['author_name'] ?? '?')[0])),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(c['author_name'] ?? '匿名', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text(_fmtTime(c['created_at']?.toString()), style: theme.textTheme.bodySmall),
                              ]),
                              const SizedBox(height: 4),
                              Text(c['content'] ?? ''),
                            ],
                          )),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _commentCtrl,
              decoration: const InputDecoration(hintText: '添加评论...', border: OutlineInputBorder(), isDense: true),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sendComment,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      ],
    );
  }

  Future<void> _submitReview(ExamModel exam) async {
    setState(() => _submitting = true);
    try {
      await ref.read(reviewRepoProvider).submitReview(exam.id, status: 'reviewed', reviewNote: _noteCtrl.text);
      if (mounted) {
        ref.invalidate(reviewListProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('复核已提交')));
        _load(); // Reload
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败: ${ApiClient.friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _undoReview(ExamModel exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销复核'),
        content: const Text('确定要撤销复核吗？检查将恢复为"待复核"状态。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定撤销')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      await ref.read(reviewRepoProvider).submitReview(exam.id, status: 'pending_review', reviewNote: _noteCtrl.text);
      if (mounted) {
        ref.invalidate(reviewListProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已撤销复核')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('撤销失败: ${ApiClient.friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final result = await ref.read(reviewRepoProvider).addComment(widget.examId, text);
      _commentCtrl.clear();
      final comment = result['comment'] as Map<String, dynamic>?;
      if (comment != null && mounted) {
        final cid = comment['id'];
        if (cid == null || !_comments.any((c) => c['id'] == cid)) {
          setState(() => _comments.add(comment));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: ${ApiClient.friendlyError(e)}')));
    }
  }

  String _fmtTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
             '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.replaceFirst('T', ' ').substring(0, raw.length >= 16 ? 16 : raw.length);
    }
  }

  void _showShareSheet(BuildContext context, ExamModel exam) {
    final parentMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => _ShareSheet(exam: exam, ref: ref, parentMessenger: parentMessenger),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textHint)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ShareSheet extends StatefulWidget {
  final ExamModel exam;
  final WidgetRef ref;
  final ScaffoldMessengerState parentMessenger;
  const _ShareSheet({required this.exam, required this.ref, required this.parentMessenger});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  String? _shareUrl;
  List<Map<String, dynamic>>? _targets;
  bool _loadingLink = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('分享病例', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // QR Share
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('生成二维码链接'),
            subtitle: _shareUrl != null ? Text(_shareUrl!, style: const TextStyle(fontSize: 12)) : null,
            onTap: _generateShareLink,
            trailing: _loadingLink ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          ),
          if (_shareUrl != null) ...[
            const SizedBox(height: 8),
            Center(child: QrImageView(data: _shareUrl!, size: 160)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _shareUrl!));
                Navigator.pop(context);
                widget.parentMessenger
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('链接已复制')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制链接'),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(),

          // Share to user
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('分享给同事'),
            onTap: _showShareToUser,
          ),
        ],
      ),
    );
  }

  Future<void> _generateShareLink() async {
    setState(() => _loadingLink = true);
    try {
      final result = await widget.ref.read(reviewRepoProvider).createShareLink(widget.exam.id);
      final link = result['link'] as Map<String, dynamic>? ?? result;
      setState(() {
        _shareUrl = link['url'] as String? ?? link['share_url'] as String?;
        _loadingLink = false;
      });
    } catch (e) {
      setState(() => _loadingLink = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: ${ApiClient.friendlyError(e)}')));
    }
  }

  Future<void> _showShareToUser() async {
    try {
      final targetList = await widget.ref.read(reviewRepoProvider).getShareTargets();
      if (!mounted) return;
      final rootMessenger = ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context);
      final router = GoRouter.of(context);
      showModalBottomSheet(
        context: context,
        builder: (_) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: targetList.length,
          itemBuilder: (ctx, i) {
            final t = targetList[i];
            return ListTile(
              leading: CircleAvatar(child: Text((t['display_name'] ?? t['username'] ?? '?')[0])),
              title: Text(t['display_name'] ?? t['username'] ?? ''),
              onTap: () async {
                Navigator.pop(ctx);        // close target list sheet
                Navigator.pop(context);    // close share sheet
                try {
                  final result = await widget.ref.read(reviewRepoProvider).shareToUser(widget.exam.id, t['id'] as int);
                  final convId = result['conversation_id'];
                  final targetName = t['display_name'] ?? t['username'] ?? '';
                  rootMessenger.showSnackBar(SnackBar(
                    content: Text('已分享给 $targetName'),
                    action: convId != null ? SnackBarAction(
                      label: '查看对话',
                      onPressed: () {
                        router.push('/doctor/chat/$convId?name=${Uri.encodeComponent(targetName)}');
                      },
                    ) : null,
                  ));
                } catch (e) {
                  rootMessenger.showSnackBar(SnackBar(content: Text('分享失败: ${ApiClient.friendlyError(e)}')));
                }
              },
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: ${ApiClient.friendlyError(e)}')));
    }
  }
}
