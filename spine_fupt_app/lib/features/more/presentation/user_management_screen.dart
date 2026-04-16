import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

const _roleLabels = {
  'admin': '管理员',
  'doctor': '医生',
  'nurse': '护士',
};

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});
  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await ref.read(overviewRepoProvider).getUsers();
      if (mounted) setState(() { _users = users; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.friendlyError(e); });
    }
  }

  Future<void> _refresh() async {
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('已刷新')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), tooltip: '创建用户', onPressed: () => _showCreateDialog()),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('重试')),
      ],
    ));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _users.isEmpty
          ? ListView(children: const [SizedBox(height: 200), Center(child: Text('暂无用户'))])
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _users.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) => _buildUserTile(_users[i], theme),
            ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> u, ThemeData theme) {
    final name = u['display_name'] ?? u['username'] ?? '?';
    final username = u['username'] ?? '';
    final role = u['role'] as String? ?? 'doctor';
    final isActive = u['is_active'] == true;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        child: Text(name[0].toUpperCase(), style: TextStyle(color: isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.outline)),
      ),
      title: Text(name),
      subtitle: Text('$username · ${_roleLabels[role] ?? role} · ${isActive ? "活跃" : "已禁用"}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showEditDialog(u),
    );
  }

  // ── Create user dialog ──
  void _showCreateDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    String selectedRole = 'doctor';
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('创建用户'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: passwordCtrl, decoration: const InputDecoration(labelText: '密码（至少6位）', border: OutlineInputBorder()), obscureText: true),
              const SizedBox(height: 12),
              TextField(controller: displayNameCtrl, decoration: const InputDecoration(labelText: '显示名称', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: '角色', border: OutlineInputBorder()),
                items: _roleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
            ],
          )),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: submitting ? null : () async {
                if (usernameCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('用户名和密码不能为空')));
                  return;
                }
                if (passwordCtrl.text.length < 6) {
                  ScaffoldMessenger.of(ctx)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('密码至少6位')));
                  return;
                }
                setDialogState(() => submitting = true);
                try {
                  await ref.read(overviewRepoProvider).createUser({
                    'username': usernameCtrl.text.trim(),
                    'password': passwordCtrl.text,
                    'display_name': displayNameCtrl.text.trim().isEmpty ? usernameCtrl.text.trim() : displayNameCtrl.text.trim(),
                    'role': selectedRole,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('用户已创建')));
                    setState(() => _loading = true);
                    _load();
                  }
                } catch (e) {
                  setDialogState(() => submitting = false);
                  if (ctx.mounted) ScaffoldMessenger.of(ctx)..clearSnackBars()..showSnackBar(SnackBar(content: Text('创建失败: ${ApiClient.friendlyError(e)}')));
                }
              },
              child: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit user dialog ──
  void _showEditDialog(Map<String, dynamic> u) {
    final uid = u['id'] as int;
    final displayNameCtrl = TextEditingController(text: u['display_name'] ?? '');
    final passwordCtrl = TextEditingController();
    String selectedRole = u['role'] as String? ?? 'doctor';
    bool isActive = u['is_active'] == true;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('编辑用户 · ${u['username']}'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: displayNameCtrl, decoration: const InputDecoration(labelText: '显示名称', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: '角色', border: OutlineInputBorder()),
                items: _roleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('启用账号'),
                value: isActive,
                onChanged: (v) => setDialogState(() => isActive = v),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              TextField(controller: passwordCtrl, decoration: const InputDecoration(labelText: '重置密码（留空不修改）', border: OutlineInputBorder()), obscureText: true),
            ],
          )),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: submitting ? null : () async {
                final patch = <String, dynamic>{};
                final newName = displayNameCtrl.text.trim();
                if (newName.isNotEmpty && newName != u['display_name']) patch['display_name'] = newName;
                if (selectedRole != u['role']) patch['role'] = selectedRole;
                if (isActive != (u['is_active'] == true)) patch['is_active'] = isActive;
                if (passwordCtrl.text.isNotEmpty) {
                  if (passwordCtrl.text.length < 6) {
                    ScaffoldMessenger.of(ctx)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('密码至少6位')));
                    return;
                  }
                  patch['password'] = passwordCtrl.text;
                }
                if (patch.isEmpty) { Navigator.pop(ctx); return; }

                setDialogState(() => submitting = true);
                try {
                  await ref.read(overviewRepoProvider).updateUser(uid, patch);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(const SnackBar(content: Text('用户已更新')));
                    setState(() => _loading = true);
                    _load();
                  }
                } catch (e) {
                  setDialogState(() => submitting = false);
                  if (ctx.mounted) ScaffoldMessenger.of(ctx)..clearSnackBars()..showSnackBar(SnackBar(content: Text('更新失败: ${ApiClient.friendlyError(e)}')));
                }
              },
              child: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
