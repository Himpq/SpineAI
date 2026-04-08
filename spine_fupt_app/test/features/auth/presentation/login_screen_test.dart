import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/features/auth/presentation/login_screen.dart';
import 'package:spine_fupt_app/providers.dart';

class MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  MockAuthNotifier() : super(const AuthState(mode: AuthMode.unauthenticated, loading: false));
}

Widget _buildTestApp({AuthState? initialState}) {
  final notifier = MockAuthNotifier();
  if (initialState != null) {
    notifier.state = initialState;
  }
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((_) => notifier),
    ],
    child: const MaterialApp(home: LoginScreen()),
  );
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders title and login form', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('脊柱随访平台'), findsOneWidget);
      expect(find.text('Spine FUPT'), findsOneWidget);
      expect(find.text('医生登录'), findsOneWidget);
      expect(find.widgetWithText(TextField, '用户名'), findsOneWidget);
      expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    });

    testWidgets('shows error when login with empty fields', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('医生登录'));
      await tester.pump();

      expect(find.text('请输入用户名和密码'), findsOneWidget);
    });

    testWidgets('toggles password visibility', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // Initially obscured
      final passwordField = tester.widget<TextField>(
          find.widgetWithText(TextField, '密码'));
      expect(passwordField.obscureText, true);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      final updated = tester.widget<TextField>(
          find.widgetWithText(TextField, '密码'));
      expect(updated.obscureText, false);
    });

    testWidgets('switches to portal mode', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // Tap portal entry
      await tester.tap(find.text('患者端入口'));
      await tester.pump();

      expect(find.text('进入患者端'), findsOneWidget);
      expect(find.text('患者Token或链接'), findsOneWidget);
      expect(find.text('返回医生登录'), findsOneWidget);
    });

    testWidgets('shows error for empty portal token', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('患者端入口'));
      await tester.pump();

      await tester.tap(find.text('进入患者端'));
      await tester.pump();

      expect(find.text('请输入患者Token'), findsOneWidget);
    });

    testWidgets('shows splash when loading', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        initialState: const AuthState(loading: true),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('脊柱随访平台'), findsOneWidget);
      // Login form should NOT be shown
      expect(find.text('医生登录'), findsNothing);
    });
  });
}
