import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers.dart';
import '../../../core/api/api_client.dart';

class ServerConfigScreen extends ConsumerStatefulWidget {
  const ServerConfigScreen({super.key});
  @override
  ConsumerState<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends ConsumerState<ServerConfigScreen> {
  late final TextEditingController _urlCtrl;
  bool _testing = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      setState(() => _result = '地址格式不正确，请以 http:// 或 https:// 开头');
      return;
    }
    setState(() { _testing = true; _result = null; });
    try {
      // Use a temporary Dio instance so we don't pollute the global ApiClient
      final tempDio = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      await tempDio.get('/healthz');
      setState(() => _result = '连接成功 ✓');
    } catch (e) {
      setState(() => _result = '连接失败: ${ApiClient.friendlyError(e)}');
    } finally {
      setState(() => _testing = false);
    }
  }

  void _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('地址格式不正确')));
      return;
    }
    ref.read(serverUrlProvider.notifier).state = url;
    ref.read(apiClientProvider).updateBaseUrl(url);
    await saveServerUrl(url);
    if (mounted) {
      ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('已保存')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器设置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.112:5000',
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 8),
            Text('当前默认地址: http://192.168.1.112:5000\n真机请确保与服务器处于同一局域网',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    child: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: FilledButton(onPressed: _save, child: const Text('保存'))),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(_result!, style: TextStyle(
                color: _result!.contains('成功') ? AppColors.success : AppColors.danger,
              )),
            ],
          ],
        ),
      ),
    );
  }
}
