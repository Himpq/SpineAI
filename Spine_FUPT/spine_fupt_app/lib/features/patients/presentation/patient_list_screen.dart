import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/shimmer_placeholders.dart';
import '../../../providers.dart';
import '../../models.dart';

class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key});
  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  final _scrollCtrl = ScrollController();
  List<PatientModel> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  String _search = '';
  Timer? _searchDebounce;

  int _lastResume = 0;

  @override
  void initState() {
    super.initState();
    _lastResume = ref.read(appResumedProvider);
    _scrollCtrl.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ref.read(patientRepoProvider).getPatientsPaginated(
        page: _page + 1,
        search: _search.isEmpty ? null : _search,
      );
      final newItems = result['items'] as List<PatientModel>;
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _page++;
          _hasMore = result['has_more'] as bool;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() { _refreshing = true; _items.clear(); _page = 0; _hasMore = true; _error = null; });
    await _loadNextPage();
    // Also invalidate shared provider for badge updates
    ref.invalidate(patientListProvider);
    if (mounted) {
      setState(() => _refreshing = false);
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已刷新'), duration: Duration(seconds: 1)));
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() { _search = value.trim(); _items.clear(); _page = 0; _hasMore = true; _error = null; });
      _loadNextPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Auto-refresh when app resumes from background
    ref.listen<int>(appResumedProvider, (prev, next) {
      if (next > _lastResume) {
        _lastResume = next;
        _doRefresh();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('患者管理'),
        actions: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _doRefresh),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索患者...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _items.isEmpty && _loading
                ? const ShimmerPatientList()
                : _items.isEmpty && _error != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 8),
                          FilledButton(onPressed: _doRefresh, child: const Text('重试')),
                        ],
                      ))
                    : _items.isEmpty
                        ? Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
                              const SizedBox(height: 16),
                              Text(_search.isEmpty ? '暂无患者' : '未找到匹配患者'),
                            ],
                          ))
                        : RefreshIndicator(
                            onRefresh: _doRefresh,
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _items.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(child: _loading
                                        ? const CircularProgressIndicator()
                                        : TextButton(onPressed: _loadNextPage, child: const Text('加载更多'))),
                                  );
                                }
                                return _PatientTile(patient: _items[i], onReturn: _doRefresh);
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'register',
            onPressed: () => context.push('/doctor/register'),
            child: const Icon(Icons.qr_code),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'addPatient',
            onPressed: () => _showAddPatientDialog(context, ref),
            child: const Icon(Icons.person_add),
          ),
        ],
      ),
    );
  }

  void _showAddPatientDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String sex = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加患者'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名 *')),
                const SizedBox(height: 12),
                TextField(controller: ageCtrl, decoration: const InputDecoration(labelText: '年龄'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '性别'),
                  value: sex.isEmpty ? null : sex,
                  items: const [
                    DropdownMenuItem(value: '男', child: Text('男')),
                    DropdownMenuItem(value: '女', child: Text('女')),
                  ],
                  onChanged: (v) => setDialogState(() => sex = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '电话'), keyboardType: TextInputType.phone),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await ref.read(patientRepoProvider).createPatient({
                    'name': nameCtrl.text.trim(),
                    if (ageCtrl.text.isNotEmpty) 'age': int.tryParse(ageCtrl.text),
                    if (sex.isNotEmpty) 'sex': sex,
                    if (phoneCtrl.text.isNotEmpty) 'phone': phoneCtrl.text.trim(),
                  });
                  ref.invalidate(patientListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _doRefresh();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ApiClient.friendlyError(e))));
                  }
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback? onReturn;
  const _PatientTile({required this.patient, this.onReturn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color statusColor = AppColors.textHint;
    String statusText = '未知';
    if (patient.status == 'follow_up') {
      statusColor = AppColors.success;
      statusText = '随访中';
    } else if (patient.status == 'pending_review') {
      statusColor = AppColors.warning;
      statusText = '待复核';
    } else if (patient.status == 'has_message' || (patient.unreadCount ?? 0) > 0) {
      statusColor = AppColors.primary;
      statusText = '有消息';
    } else {
      statusText = '正常';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(patient.name.isNotEmpty ? patient.name[0] : '?',
              style: TextStyle(color: theme.colorScheme.primary)),
        ),
        title: Text(patient.name),
        subtitle: Text([
          if (patient.age != null) '${patient.age}岁',
          if (patient.sex != null && patient.sex!.isNotEmpty) patient.sex!,
          if (patient.lastExamDate != null && patient.lastExamDate!.length >= 10) '最近检查: ${patient.lastExamDate!.substring(0, 10)}',
        ].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
            ),
            if ((patient.unreadCount ?? 0) > 0) ...[
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.danger,
                child: Text('${patient.unreadCount}', style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ],
          ],
        ),
        onTap: () async {
          await context.push('/doctor/patients/${patient.id}');
          onReturn?.call();
        },
      ),
    );
  }
}
