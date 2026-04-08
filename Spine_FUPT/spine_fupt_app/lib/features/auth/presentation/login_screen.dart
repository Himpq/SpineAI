import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _portalTokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showPortal = false;
  bool _obscure = true;
  List<Map<String, dynamic>> _portalHistory = [];

  @override
  void initState() {
    super.initState();
    _loadPortalHistory();
  }

  Future<void> _loadPortalHistory() async {
    final history = await ref.read(authProvider.notifier).getPortalHistory();
    if (mounted) setState(() => _portalHistory = history);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _portalTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    if (_usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(_usernameCtrl.text.trim(), _passwordCtrl.text);
      if (mounted) context.go('/doctor/overview');
    } catch (e) {
      setState(() => _error = ApiClient.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enterPortal() async {
    final token = _portalTokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = '请输入患者Token');
      return;
    }
    // Extract token from URL if pasted full URL
    String finalToken = token;
    if (token.contains('/portal/')) {
      finalToken = token.split('/portal/').last.split('?').first;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).enterPortal(finalToken);
      if (mounted) context.go('/portal/home');
    } catch (e) {
      setState(() => _error = ApiClient.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    // Show splash while checking session OR while waiting for router redirect after successful restore
    if (auth.loading || auth.mode != AuthMode.unauthenticated) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.medical_services, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('脊柱随访平台', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.medical_services, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('脊柱随访平台', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Spine FUPT', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 40),

                if (!_showPortal) ...[
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.person)),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _doLogin(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('医生登录'),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _portalTokenCtrl,
                    decoration: const InputDecoration(
                      labelText: '患者Token或链接',
                      prefixIcon: Icon(Icons.key),
                      hintText: '粘贴portal链接或token',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _enterPortal(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _enterPortal,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('进入患者端'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => context.push('/qr-scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码登录'),
                    ),
                  ),
                  // Login history
                  if (_portalHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('最近登录', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    const SizedBox(height: 8),
                    ..._portalHistory.map((entry) {
                      final name = entry['name'] as String? ?? '患者';
                      final token = entry['token'] as String? ?? '';
                      final ts = entry['timestamp'] as String?;
                      String timeStr = '';
                      if (ts != null) {
                        try {
                          final dt = DateTime.parse(ts);
                          timeStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        } catch (_) {}
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _loading ? null : () async {
                            setState(() { _loading = true; _error = null; });
                            try {
                              await ref.read(authProvider.notifier).enterPortal(token);
                              if (mounted) context.go('/portal/home');
                            } catch (e) {
                              setState(() => _error = ApiClient.friendlyError(e));
                            } finally {
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                  child: Text(name[0], style: TextStyle(fontSize: 14, color: theme.colorScheme.primary)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                      if (timeStr.isNotEmpty)
                                        Text(timeStr, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    await ref.read(authProvider.notifier).removeFromHistory(token);
                                    _loadPortalHistory();
                                  },
                                  child: Icon(Icons.close, size: 16, color: theme.colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],

                const SizedBox(height: 16),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() { _showPortal = !_showPortal; _error = null; }),
                  child: Text(_showPortal ? '返回医生登录' : '患者端入口'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/server-config'),
                  child: Text('服务器设置', style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/trial/upload'),
                    icon: const Icon(Icons.science),
                    label: const Text('体验AI推理'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
