import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../providers.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _sex;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if any
    final auth = ref.read(authProvider);
    final p = auth.portalData?['patient'] as Map<String, dynamic>? ?? {};
    _nameCtrl.text = p['name'] as String? ?? '';
    if (p['age'] != null) _ageCtrl.text = p['age'].toString();
    _sex = p['sex'] as String?;
    _phoneCtrl.text = p['phone'] as String? ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写姓名');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final token = ref.read(authProvider).portalToken!;
      await ref.read(apiClientProvider).post(
        ApiEndpoints.publicPortalProfile(token),
        data: {
          'name': name,
          if (_ageCtrl.text.trim().isNotEmpty) 'age': int.tryParse(_ageCtrl.text.trim()),
          if (_sex != null) 'sex': _sex,
          if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        },
      );
      // Refresh portal data
      await ref.read(authProvider.notifier).enterPortal(token);
      if (mounted) context.go('/portal/home');
    } catch (e) {
      setState(() => _error = ApiClient.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('完善个人信息')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.person_add, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('请填写您的基本信息', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '姓名 *', prefixIcon: Icon(Icons.person)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ageCtrl,
              decoration: const InputDecoration(labelText: '年龄', prefixIcon: Icon(Icons.cake)),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _sex,
              decoration: const InputDecoration(labelText: '性别', prefixIcon: Icon(Icons.wc)),
              items: const [
                DropdownMenuItem(value: '男', child: Text('男')),
                DropdownMenuItem(value: '女', child: Text('女')),
              ],
              onChanged: (v) => setState(() => _sex = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: '电话', prefixIcon: Icon(Icons.phone)),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('提交'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
