import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/api/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted prefs first
  final container = ProviderContainer();
  await loadSavedPrefs(container);
  final savedUrl = container.read(serverUrlProvider);
  await ApiClient.getInstance(baseUrl: savedUrl);

  runApp(UncontrolledProviderScope(container: container, child: const SpineFuptApp()));
}

class SpineFuptApp extends ConsumerStatefulWidget {
  const SpineFuptApp({super.key});
  @override
  ConsumerState<SpineFuptApp> createState() => _SpineFuptAppState();
}

class _SpineFuptAppState extends ConsumerState<SpineFuptApp> with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = createRouter(ref);
    // Wire 401 auto-logout: when server returns 401, force logout
    ApiClient.instance.onUnauthorized = () {
      final auth = ref.read(authProvider);
      if (auth.mode != AuthMode.unauthenticated) {
        ref.read(authProvider.notifier).logout();
      }
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = ref.read(authProvider);
    if (state == AppLifecycleState.resumed && auth.mode != AuthMode.unauthenticated) {
      // Reconnect WebSocket when app comes back to foreground
      final ws = ref.read(wsClientProvider);
      if (!ws.isConnected) {
        final url = ref.read(serverUrlProvider);
        if (auth.mode == AuthMode.doctor && auth.user != null) {
          ws.connect(url, kind: 'doctor', name: auth.user!.displayName, userId: auth.user!.id);
          ws.subscribe('system');
          ws.subscribe('patients');
        } else if (auth.mode == AuthMode.patient) {
          ws.connect(url, kind: 'patient', name: auth.portalData?['patient']?['name'] ?? '患者');
          ws.subscribe('system');
        }
      }

      // Bump resume counter so screens with local state can react
      ref.read(appResumedProvider.notifier).state++;

      // Refresh data that may have changed while in background
      if (auth.mode == AuthMode.doctor) {
        ref.invalidate(overviewProvider);
        ref.invalidate(conversationListProvider);
        ref.invalidate(patientListProvider);
        ref.invalidate(reviewListProvider);
        ref.invalidate(questionnaireListProvider);
      } else if (auth.mode == AuthMode.patient && auth.portalToken != null) {
        ref.read(authProvider.notifier).enterPortal(auth.portalToken!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth to trigger router redirect
    ref.watch(authProvider);

    // Listen for toast notifications from WS
    ref.listen<ToastMessage?>(toastStreamProvider, (prev, next) {
      if (next != null && _router.routerDelegate.navigatorKey.currentContext != null) {
        final ctx = _router.routerDelegate.navigatorKey.currentContext!;
        final theme = Theme.of(ctx);
        final color = next.level == 'error' ? theme.colorScheme.error
            : next.level == 'warning' ? Colors.orange
            : theme.colorScheme.primary;
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Row(children: [
              Icon(next.level == 'error' ? Icons.error : Icons.notifications_active, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (next.title.isNotEmpty) Text(next.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  if (next.message.isNotEmpty) Text(next.message, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              )),
            ]),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ));
      }
    });

    return MaterialApp.router(
      title: '脊柱AI影像随访',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
    );
  }
}

