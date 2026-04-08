import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TrialShell extends StatelessWidget {
  final Widget child;
  const TrialShell({super.key, required this.child});

  static const _tabs = [
    ('/trial/home', '首页', Icons.home_outlined, Icons.home),
    ('/trial/timeline', '随访', Icons.timeline_outlined, Icons.timeline),
    ('/trial/upload', '上传', Icons.add_a_photo_outlined, Icons.add_a_photo),
    ('/trial/chat', '聊天', Icons.chat_outlined, Icons.chat),
    ('/trial/ai-doctor', 'AI医生', Icons.smart_toy_outlined, Icons.smart_toy),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);

    return Scaffold(
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
    );
  }
}
