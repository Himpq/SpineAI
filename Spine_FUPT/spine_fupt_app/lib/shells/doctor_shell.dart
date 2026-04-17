import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../providers.dart';

class DoctorShell extends ConsumerWidget {
  final Widget child;
  const DoctorShell({super.key, required this.child});

  static const _tabs = [
    ('/doctor/overview', '总览', Icons.dashboard_outlined, Icons.dashboard),
    ('/doctor/patients', '患者', Icons.people_outline, Icons.people),
    ('/doctor/reviews', '复核', Icons.biotech_outlined, Icons.biotech),
    ('/doctor/chat', '聊天', Icons.chat_outlined, Icons.chat),
    ('/doctor/questionnaires', '问卷', Icons.assignment_outlined, Icons.assignment),
    ('/doctor/more', '更多', Icons.more_horiz_outlined, Icons.more_horiz),
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
    final chatUnread = ref.watch(chatUnreadCountProvider);
    final pendingReviews = ref.watch(pendingReviewCountProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    final wsConnected = ref.watch(wsConnectedProvider);

    return PopScope(
      canPop: idx == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go('/doctor/overview');
        }
      },
      child: Column(
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
            )
          else if (!wsConnected)
            Material(
              color: AppColors.warning,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('正在重新连接...', style: AppTextStyles.caption.copyWith(color: Colors.white))),
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
          destinations: _tabs.asMap().entries.map((e) {
            final i = e.key;
            final t = e.value;
            final int badgeCount;
            if (i == 2) { badgeCount = pendingReviews; }      // 复核
            else if (i == 3) { badgeCount = chatUnread; }      // 聊天
            else { badgeCount = 0; }

            Widget icon = Icon(t.$3);
            Widget selectedIcon = Icon(t.$4);
            if (badgeCount > 0) {
              icon = Badge(label: Text('$badgeCount'), child: icon);
              selectedIcon = Badge(label: Text('$badgeCount'), child: selectedIcon);
            }
            return NavigationDestination(
              icon: icon,
              selectedIcon: selectedIcon,
              label: t.$2,
            );
          }).toList(),
        ),
      )),
        ],
      ),
    );
  }
}
