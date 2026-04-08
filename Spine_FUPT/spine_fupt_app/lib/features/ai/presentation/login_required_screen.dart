import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// Placeholder screen shown for features that require login.
class LoginRequiredScreen extends StatelessWidget {
  final String featureName;
  const LoginRequiredScreen({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('请登录后使用',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('$featureName功能需要登录后才能使用',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login),
                label: const Text('前往登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
