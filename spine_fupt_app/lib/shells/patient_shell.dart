import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../providers.dart';

class PatientShell extends ConsumerWidget {
  final Widget child;
  const PatientShell({super.key, required this.child});

  static const _tabs = [
    ('/portal/home', '首页', Icons.home_outlined, Icons.home),
    ('/portal/timeline', '随访', Icons.timeline_outlined, Icons.timeline),
    ('/portal/upload', '上传', Icons.add_a_photo_outlined, Icons.add_a_photo),
    ('/portal/chat', '聊天', Icons.chat_outlined, Icons.chat),
    ('/portal/ai-doctor', 'AI医生', Icons.smart_toy_outlined, Icons.smart_toy),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _currentIndex(context);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    return Column(
      children: [
        if (!isOnline)
          Material(
            color: AppColors.danger,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('当前无网络连接', style: AppTextStyles.caption.copyWith(color: Colors.white))),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          if (i != idx) context.go(_tabs[i].$1);
        },
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.$3),
                  selectedIcon: Icon(t.$4),
                  label: t.$2,
                ))
            .toList(),
      ),
    )),
      ],
    );
  }
}
