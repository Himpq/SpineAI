import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../providers.dart';

class RegistrationFormScreen extends ConsumerStatefulWidget {
  final String regToken;
  const RegistrationFormScreen({super.key, required this.regToken});
  @override
  ConsumerState<RegistrationFormScreen> createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends ConsumerState<RegistrationFormScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _sex;
  bool _loading = false;
  bool _initialLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get(ApiEndpoints.publicRegister(widget.regToken));
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final status = data['status'] as String? ?? '';
      final patient = data['patient'] as Map<String, dynamic>?;

      // Already submitted — auto-login
      if (status == 'submitted' && patient != null) {
        final portalToken = patient['portal_token'] as String?;
        if (portalToken != null && portalToken.isNotEmpty) {
          await ref.read(authProvider.notifier).enterPortal(portalToken);
          if (mounted) context.go('/portal/home');
          return;
        }
      }

      // Pre-fill form from existing form_state
      final formState = data['form_state'] as Map<String, dynamic>? ?? {};
      _nameCtrl.text = (formState['name'] as String?) ?? '';
      if (formState['age'] != null) _ageCtrl.text = formState['age'].toString();
      _sex = formState['sex'] as String?;
      _phoneCtrl.text = (formState['phone'] as String?) ?? '';
    } catch (e) {
      _error = ApiClient.friendlyError(e);
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
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
      final api = ref.read(apiClientProvider);
      final resp = await api.post(
        ApiEndpoints.publicRegisterSubmit(widget.regToken),
        data: {
          'actor_name': name,
          'form_state': {
            'name': name,
            if (_ageCtrl.text.trim().isNotEmpty) 'age': _ageCtrl.text.trim(),
            if (_sex != null) 'sex': _sex,
            if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
          },
        },
      );

      // Extract portal_token from response and auto-login
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final portalToken = data['portal_token'] as String?;
      if (portalToken == null || portalToken.isEmpty) {
        setState(() => _error = '登记成功但未获取到登录信息，请联系医生');
        return;
      }

      await ref.read(authProvider.notifier).enterPortal(portalToken);
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

    if (_initialLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('患者登记')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('患者登记')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.how_to_reg, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('请填写您的基本信息完成登记', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
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
                    : const Text('提交并登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
