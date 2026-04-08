import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class SharedCaseScreen extends ConsumerStatefulWidget {
  final String token;
  const SharedCaseScreen({super.key, required this.token});
  @override
  ConsumerState<SharedCaseScreen> createState() => _SharedCaseScreenState();
}

class _SharedCaseScreenState extends ConsumerState<SharedCaseScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _showAi = true;
  final _commentCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadSavedName();
    _load();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('visitor_name') ?? '';
    if (name.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = name;
    }
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('visitor_name', name);
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(portalRepoProvider).getPublicCase(widget.token);
      if (mounted) {
        final exam = res['exam'] as Map<String, dynamic>? ?? res;
        setState(() {
          _data = exam;
          _comments = (exam['comments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loading = false;
          _error = null;
        });
        // Subscribe to comment channel
        final ch = exam['comment_channel'] as String?;
        if (ch != null) {
          final ws = ref.read(wsClientProvider);
          ws.subscribe(ch);
          ws.on('case_comment', (payload) {
            if (!mounted) return;
            final comment = payload['comment'] as Map<String, dynamic>? ?? payload;
            final cid = comment['id'];
            if (cid != null && _comments.any((c) => c['id'] == cid)) return;
            setState(() => _comments.add(comment));
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  @override
  void dispose() {
    final ch = _data?['comment_channel'] as String?;
    if (ch != null) ref.read(wsClientProvider).unsubscribe(ch);
    _commentCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('病例查看')), body: const Center(child: CircularProgressIndicator()));
    if (_data == null) return Scaffold(appBar: AppBar(title: const Text('病例查看')), body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error ?? '加载失败或链接无效'),
        const SizedBox(height: 8),
        FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('重试')),
      ],
    )));

    final exam = _data!;
    final baseUrl = ref.read(serverUrlProvider);
    final rawImageUrl = exam['raw_image_url'] as String?;
    final inferenceUrl = exam['inference_image_url'] as String?;
    final cobbAngle = (exam['cobb_angle'] as num?)?.toDouble();
    final severity = exam['severity_label'] as String?;
    final spineClass = exam['spine_class_text'] as String?;
    final patientName = exam['patient_name'] as String?;
    final cervicalMetric = exam['cervical_metric'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: Text(patientName ?? '病例查看')),
      body: Column(
        children: [
          // Image
          Expanded(
            flex: 50,
            child: Container(
              color: Colors.black,
              child: _buildImage(baseUrl, _showAi ? (inferenceUrl ?? rawImageUrl) : rawImageUrl),
            ),
          ),
          // AI/Raw toggle (outside image to avoid gesture conflicts)
          if (inferenceUrl != null && rawImageUrl != null)
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
          // Info + comments
          Expanded(
            flex: 50,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(tabs: const [Tab(text: '信息'), Tab(text: '评论')]),
                  Expanded(child: TabBarView(children: [
                    // Info
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (spineClass != null) _InfoItem('分类', spineClass),
                        if (cobbAngle != null) _InfoItem('Cobb角', '${cobbAngle.toStringAsFixed(1)}°'),
                        if (severity != null) _InfoItem('严重程度', severity),
                        if (cervicalMetric != null) ...[
                          if (cervicalMetric['avg_ratio'] != null)
                            _InfoItem('平均比率', cervicalMetric['avg_ratio'].toString()),
                          if (cervicalMetric['left_ratio'] != null)
                            _InfoItem('左侧比率', cervicalMetric['left_ratio'].toString()),
                          if (cervicalMetric['right_ratio'] != null)
                            _InfoItem('右侧比率', cervicalMetric['right_ratio'].toString()),
                          if (cervicalMetric['assessment'] != null)
                            _InfoItem('评估', cervicalMetric['assessment'].toString()),
                        ],
                      ],
                    ),
                    // Comments
                    Column(
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
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        CircleAvatar(radius: 14, child: Text((c['author_name'] ?? '?')[0], style: const TextStyle(fontSize: 12))),
                                        const SizedBox(width: 8),
                                        Expanded(child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(c['author_name'] ?? '访客', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 8),
                                              Flexible(child: Text(_formatTime(c['created_at']?.toString()), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline), overflow: TextOverflow.ellipsis)),
                                            ]),
                                            const SizedBox(height: 2),
                                            Text(c['content'] ?? ''),
                                          ],
                                        )),
                                      ]),
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                          child: TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(hintText: '昵称（可选）', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.person_outline, size: 20)),
                            onChanged: _saveName,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Row(children: [
                            Expanded(child: TextField(
                              controller: _commentCtrl,
                              decoration: const InputDecoration(hintText: '添加评论...', border: OutlineInputBorder(), isDense: true),
                            )),
                            const SizedBox(width: 8),
                            IconButton.filled(onPressed: _sending ? null : _sendComment, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send)),
                          ]),
                        ),
                      ],
                    ),
                  ])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(String baseUrl, String? url) {
    if (url == null) return const Center(child: Icon(Icons.image_not_supported, color: Colors.white38, size: 64));
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    return PhotoView(
      key: ValueKey(fullUrl),
      imageProvider: NetworkImage(fullUrl),
      minScale: PhotoViewComputedScale.contained * 0.3,
      maxScale: PhotoViewComputedScale.covered * 6.0,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final name = _nameCtrl.text.trim();
      await ref.read(portalRepoProvider).addPublicComment(widget.token, content: text, authorName: name.isEmpty ? '访客' : name);
      _commentCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('发送失败: ${ApiClient.friendlyError(e)}')));
    }
    if (mounted) setState(() => _sending = false);
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
             '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.replaceFirst('T', ' ');
    }
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: const TextStyle(color: AppColors.textHint)), Text(value, style: const TextStyle(fontWeight: FontWeight.w500))],
      ),
    );
  }
}
