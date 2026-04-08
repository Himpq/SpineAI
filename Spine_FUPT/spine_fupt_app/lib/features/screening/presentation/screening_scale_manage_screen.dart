import 'package:flutter/material.dart';
import '../data/screening_scale_repository.dart';
import '../../../core/theme/app_theme.dart';

/// 医生端 — 筛查量表管理列表
class ScreeningScaleListScreen extends StatefulWidget {
  const ScreeningScaleListScreen({super.key});
  @override
  State<ScreeningScaleListScreen> createState() => _ScreeningScaleListScreenState();
}

class _ScreeningScaleListScreenState extends State<ScreeningScaleListScreen> {
  List<Map<String, dynamic>> _scales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _scales = await ScreeningScaleRepository().getScales();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除此量表吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ScreeningScaleRepository().deleteScale(id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('筛查量表管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ScreeningScaleEditScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('加载失败', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_error!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ]))
              : _scales.isEmpty
                  ? const Center(child: Text('暂无筛查量表'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _scales.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final s = _scales[i];
                          final color = _parseColor(s['color'] as String? ?? '#3478F6');
                          return Card(
                            child: ListTile(
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Icon(_mapIcon(s['icon'] as String?), color: color, size: 22),
                              ),
                              title: Text(s['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(s['subtitle'] ?? '', style: TextStyle(color: color, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (s['is_preset'] == true) Chip(label: const Text('预设', style: TextStyle(fontSize: 10)), padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ScreeningScaleEditScreen(scaleId: s['id'] as int)));
                                        if (result == true) _load();
                                      } else if (v == 'delete') {
                                        _delete(s['id'] as int);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ScreeningScaleEditScreen(scaleId: s['id'] as int)));
                                if (result == true) _load();
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
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
      'compare_arrows': Icons.compare_arrows,
      'straighten': Icons.straighten,
      'balance': Icons.balance,
      'airline_seat_flat': Icons.airline_seat_flat,
      'family_restroom': Icons.family_restroom,
    };
    return map[name] ?? Icons.quiz;
  }
}

// ─── 编辑页面 ─────────────────────────────────────────────────────

class ScreeningScaleEditScreen extends StatefulWidget {
  final int? scaleId;
  const ScreeningScaleEditScreen({super.key, this.scaleId});
  @override
  State<ScreeningScaleEditScreen> createState() => _ScreeningScaleEditScreenState();
}

class _ScreeningScaleEditScreenState extends State<ScreeningScaleEditScreen> {
  final _repo = ScreeningScaleRepository();
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _scaleType = 'weighted';
  int _maxScore = 0;
  bool _loading = false;
  bool _saving = false;

  final List<Map<String, dynamic>> _items = [];
  final List<Map<String, dynamic>> _ranges = [];

  bool get _isEdit => widget.scaleId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final data = await _repo.getScale(widget.scaleId!);
      _titleCtrl.text = data['title'] ?? '';
      _subtitleCtrl.text = data['subtitle'] ?? '';
      _descCtrl.text = data['description'] ?? '';
      _scaleType = data['scale_type'] ?? 'weighted';
      _maxScore = data['max_score'] ?? 0;
      _items.clear();
      for (final it in (data['items'] as List? ?? [])) {
        _items.add(Map<String, dynamic>.from(it));
      }
      _ranges.clear();
      for (final r in (data['result_ranges'] as List? ?? [])) {
        _ranges.add(Map<String, dynamic>.from(r));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写量表标题')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'title': title,
        'subtitle': _subtitleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'scale_type': _scaleType,
        'max_score': _maxScore,
        'items': _items,
        'result_ranges': _ranges,
      };
      if (_isEdit) {
        await _repo.updateScale(widget.scaleId!, body);
      } else {
        await _repo.createScale(body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addItem() {
    setState(() {
      _items.add({
        'title': '',
        'description': '',
        'q_type': _scaleType == 'yes_no' ? 'yes_no' : _scaleType == 'slider' ? 'slider' : 'scored',
        'options': _scaleType == 'weighted' ? <Map<String, dynamic>>[{'text': '', 'weight': 0}] : null,
        'slider_min': 0.0,
        'slider_max': 10.0,
        'slider_step': 0.1,
        'slider_min_label': '',
        'slider_max_label': '',
      });
    });
  }

  void _addRange() {
    setState(() {
      _ranges.add({'min_score': 0.0, 'max_score': 0.0, 'level_text': '', 'color': '#34C759', 'suggestions': <String>[]});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑量表' : '新建量表'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic info
                  TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '量表标题 *', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _subtitleCtrl, decoration: const InputDecoration(labelText: '副标题', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder()), maxLines: 2),
                  const SizedBox(height: 12),
                  // Scale type
                  DropdownButtonFormField<String>(
                    value: _scaleType,
                    decoration: const InputDecoration(labelText: '量表类型', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'weighted', child: Text('加权评分（NDI/ODI等）')),
                      DropdownMenuItem(value: 'yes_no', child: Text('是/否判断（IOF等）')),
                      DropdownMenuItem(value: 'slider', child: Text('滑块评分（VAS等）')),
                    ],
                    onChanged: (v) => setState(() => _scaleType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(labelText: '满分', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: '$_maxScore'),
                    onChanged: (v) => _maxScore = int.tryParse(v) ?? 0,
                  ),
                  const SizedBox(height: 24),

                  // ─── Items ──────────────────────────────────────
                  Row(
                    children: [
                      Text('题目列表', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add, size: 18), label: const Text('添加题目')),
                    ],
                  ),
                  const Divider(),
                  ..._items.asMap().entries.map((e) => _buildItemCard(e.key, e.value, theme)),
                  if (_items.isEmpty) const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('暂无题目，点击上方"添加题目"', style: TextStyle(color: AppColors.textSecondary))),
                  ),
                  const SizedBox(height: 24),

                  // ─── Result ranges ─────────────────────────────
                  Row(
                    children: [
                      Text('结果分级', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(onPressed: _addRange, icon: const Icon(Icons.add, size: 18), label: const Text('添加分级')),
                    ],
                  ),
                  const Divider(),
                  ..._ranges.asMap().entries.map((e) => _buildRangeCard(e.key, e.value, theme)),
                  if (_ranges.isEmpty) const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('暂无结果分级，点击上方"添加分级"', style: TextStyle(color: AppColors.textSecondary))),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildItemCard(int idx, Map<String, dynamic> item, ThemeData theme) {
    final qType = item['q_type'] as String? ?? 'scored';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('${idx + 1}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: item['title'] as String? ?? '',
                    decoration: const InputDecoration(labelText: '题目标题', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => item['title'] = v,
                  ),
                ),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => setState(() => _items.removeAt(idx))),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: item['description'] as String? ?? '',
              decoration: const InputDecoration(labelText: '描述（可选）', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => item['description'] = v,
            ),
            if (qType == 'scored') ...[
              const SizedBox(height: 8),
              Text('选项 (文本 + 权重)', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              ..._buildOptionsList(item),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加选项'),
                onPressed: () {
                  setState(() {
                    final opts = List<Map<String, dynamic>>.from(item['options'] ?? []);
                    opts.add({'text': '', 'weight': opts.length});
                    item['options'] = opts;
                  });
                },
              ),
            ],
            if (qType == 'slider') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextFormField(
                    initialValue: '${item['slider_min'] ?? 0}',
                    decoration: const InputDecoration(labelText: '最小值', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => item['slider_min'] = double.tryParse(v) ?? 0,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(
                    initialValue: '${item['slider_max'] ?? 10}',
                    decoration: const InputDecoration(labelText: '最大值', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => item['slider_max'] = double.tryParse(v) ?? 10,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(
                    initialValue: '${item['slider_step'] ?? 0.1}',
                    decoration: const InputDecoration(labelText: '步长', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => item['slider_step'] = double.tryParse(v) ?? 0.1,
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextFormField(
                    initialValue: item['slider_min_label'] as String? ?? '',
                    decoration: const InputDecoration(labelText: '最小值标签', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => item['slider_min_label'] = v,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(
                    initialValue: item['slider_max_label'] as String? ?? '',
                    decoration: const InputDecoration(labelText: '最大值标签', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => item['slider_max_label'] = v,
                  )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOptionsList(Map<String, dynamic> item) {
    final opts = List<Map<String, dynamic>>.from(item['options'] ?? []);
    return opts.asMap().entries.map((e) {
      final i = e.key;
      final opt = e.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(width: 20, child: Text('${i + 1}.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
              flex: 3,
              child: TextFormField(
                initialValue: opt['text'] as String? ?? '',
                decoration: const InputDecoration(hintText: '选项文本', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) {
                  opts[i]['text'] = v;
                  item['options'] = opts;
                },
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 60,
              child: TextFormField(
                initialValue: '${opt['weight'] ?? 0}',
                decoration: const InputDecoration(hintText: '权重', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                style: const TextStyle(fontSize: 13),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  opts[i]['weight'] = int.tryParse(v) ?? 0;
                  item['options'] = opts;
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.red),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                setState(() {
                  opts.removeAt(i);
                  item['options'] = opts;
                });
              },
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildRangeCard(int idx, Map<String, dynamic> range, ThemeData theme) {
    final suggestionsCtrl = TextEditingController(
      text: (range['suggestions'] as List?)?.join('\n') ?? '',
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: TextFormField(
                  initialValue: range['level_text'] as String? ?? '',
                  decoration: const InputDecoration(labelText: '等级名称', border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => range['level_text'] = v,
                )),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => setState(() => _ranges.removeAt(idx))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextFormField(
                  initialValue: '${range['min_score'] ?? 0}',
                  decoration: const InputDecoration(labelText: '最低分', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => range['min_score'] = double.tryParse(v) ?? 0,
                )),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(
                  initialValue: '${range['max_score'] ?? 0}',
                  decoration: const InputDecoration(labelText: '最高分', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => range['max_score'] = double.tryParse(v) ?? 0,
                )),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(
                  initialValue: range['color'] as String? ?? '#34C759',
                  decoration: const InputDecoration(labelText: '颜色(Hex)', border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => range['color'] = v,
                )),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: range['description'] as String? ?? '',
              decoration: const InputDecoration(labelText: '结果描述', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => range['description'] = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: suggestionsCtrl,
              decoration: const InputDecoration(labelText: '建议措施（每行一条）', border: OutlineInputBorder(), isDense: true),
              maxLines: 3,
              onChanged: (v) => range['suggestions'] = v.split('\n').where((l) => l.trim().isNotEmpty).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
