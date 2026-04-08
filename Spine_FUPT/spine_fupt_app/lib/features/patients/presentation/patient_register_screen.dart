import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class PatientRegisterScreen extends ConsumerStatefulWidget {
  final int? patientId;
  const PatientRegisterScreen({super.key, this.patientId});
  @override
  ConsumerState<PatientRegisterScreen> createState() => _PatientRegisterScreenState();
}

class _PatientRegisterScreenState extends ConsumerState<PatientRegisterScreen> {
  Map<String, dynamic>? _session;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _formState = {};
  String? _focusField;
  bool _submitted = false;
  Map<String, dynamic>? _patient;

  @override
  void initState() {
    super.initState();
    _createSession();
  }

  Future<void> _createSession() async {
    try {
      final data = await ref.read(patientRepoProvider).createRegistrationSession();
      setState(() {
        _session = data;
        _loading = false;
      });
      _setupWs();
    } catch (e) {
      setState(() { _error = ApiClient.friendlyError(e); _loading = false; });
    }
  }

  void _setupWs() {
    final token = _session?['token'];
    if (token == null) return;
    final ws = ref.read(wsClientProvider);
    final channel = 'form:$token';
    ws.subscribe(channel);

    ws.on('field_focus', (msg) {
      if (mounted) setState(() => _focusField = msg['field'] as String?);
    });
    ws.on('field_change', (msg) {
      if (mounted) {
        setState(() {
          _formState[msg['field'] as String] = msg['value'];
        });
      }
    });
    ws.on('form_submit', (msg) {
      if (mounted) {
        setState(() {
          _submitted = true;
          _formState = (msg['form_state'] as Map<String, dynamic>?) ?? _formState;
          _patient = msg['patient'] as Map<String, dynamic>?;
        });
      }
    });
  }

  @override
  void dispose() {
    final token = _session?['token'];
    if (token != null) {
      ref.read(wsClientProvider).unsubscribe('form:$token');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('患者登记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('错误: $_error'))
              : _submitted
                  ? _buildSubmitted(theme)
                  : _buildWaiting(theme),
    );
  }

  Widget _buildWaiting(ThemeData theme) {
    final registerUrl = _session?['register_url'] ?? '';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('扫描二维码进行登记', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: registerUrl,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(registerUrl, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),

        const SizedBox(height: 32),
        Text('实时填写状态', style: theme.textTheme.titleSmall),
        const Divider(),
        const SizedBox(height: 8),

        if (_formState.isEmpty)
          Text('等待患者开始填写...', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center)
        else
          ...['name', 'age', 'sex', 'phone', 'email', 'note'].map((field) {
            final value = _formState[field]?.toString() ?? '';
            final isFocused = _focusField == field;
            final labels = {'name': '姓名', 'age': '年龄', 'sex': '性别', 'phone': '电话', 'email': '邮箱', 'note': '备注'};
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isFocused ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
                color: isFocused ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null,
              ),
              child: Row(
                children: [
                  SizedBox(width: 50, child: Text(labels[field] ?? field, style: theme.textTheme.bodySmall)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(value.isEmpty ? '-' : value, style: theme.textTheme.bodyMedium)),
                  if (isFocused) Icon(Icons.edit, size: 16, color: theme.colorScheme.primary),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSubmitted(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 72, color: AppColors.success),
            const SizedBox(height: 16),
            Text('登记完成', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (_patient != null) ...[
              Text('患者: ${_patient!['name']}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  final pid = _patient!['id'];
                  if (pid != null) {
                    ref.invalidate(patientListProvider);
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('返回'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
