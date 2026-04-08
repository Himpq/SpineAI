import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spine_fupt_app/features/auth/presentation/login_screen.dart';
import 'package:spine_fupt_app/providers.dart';

/// Integration smoke test — requires a running emulator/device.
///
/// Run with:
///   flutter test integration_test/smoke_test.dart
///
/// Or on a connected device:
///   flutter test integration_test/ -d [device-id]
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Smoke: Login flow', () {
    testWidgets('app boots to login screen and form is interactive', (tester) async {
      // Build a minimal app with unauthenticated state
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((_) => _FakeAuthNotifier()),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // ① Login screen renders
      expect(find.text('脊柱随访平台'), findsOneWidget);
      expect(find.text('医生登录'), findsOneWidget);

      // ② Enter username & password
      await tester.enterText(find.widgetWithText(TextField, '用户名'), 'admin');
      await tester.enterText(find.widgetWithText(TextField, '密码'), 'admin123');
      await tester.pump();

      // ③ Tap login — since we use a fake notifier that throws,
      //    the error container should appear
      await tester.tap(find.text('医生登录'));
      await tester.pumpAndSettle();

      // The fake notifier throws, so an error message should be visible
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('portal mode toggle works', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((_) => _FakeAuthNotifier()),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to portal mode
      await tester.tap(find.text('患者端入口'));
      await tester.pumpAndSettle();

      expect(find.text('进入患者端'), findsOneWidget);
      expect(find.text('患者Token或链接'), findsOneWidget);

      // Switch back
      await tester.tap(find.text('返回医生登录'));
      await tester.pumpAndSettle();

      expect(find.text('医生登录'), findsOneWidget);
    });
  });
}

/// Minimal fake AuthNotifier that stays unauthenticated and
/// throws on login (simulates server unreachable).
class _FakeAuthNotifier extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuthNotifier() : super(const AuthState(mode: AuthMode.unauthenticated, loading: false));

  @override
  Future<void> login(String username, String password) async {
    throw Exception('集成测试: 模拟登录失败');
  }

  @override
  Future<void> enterPortal(String token) async {
    throw Exception('集成测试: 模拟进入患者端失败');
  }

  @override
  Future<void> logout() async {
    state = const AuthState(mode: AuthMode.unauthenticated, loading: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
