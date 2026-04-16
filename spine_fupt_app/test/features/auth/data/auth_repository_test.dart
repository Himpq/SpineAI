import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/auth/data/auth_repository.dart';
import 'package:spine_fupt_app/features/auth/domain/user_model.dart';
import '../../../helpers/mock_api_client.dart';

void main() {
  late MockApiClient api;
  late AuthRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = AuthRepository(api);
  });

  group('checkSession', () {
    test('returns UserModel when session is valid', () async {
      when(() => api.get(ApiEndpoints.authSession)).thenAnswer((_) async => {
            'ok': true,
            'data': {
              'user': {
                'id': 1,
                'username': 'admin',
                'display_name': '管理员',
                'role': 'admin',
                'is_active': true,
                'modules': ['patients', 'reviews'],
              }
            },
          });

      final user = await repo.checkSession();
      expect(user, isNotNull);
      expect(user!.id, 1);
      expect(user.username, 'admin');
      expect(user.isAdmin, true);
    });

    test('returns null when session is invalid', () async {
      when(() => api.get(ApiEndpoints.authSession)).thenAnswer((_) async => {
            'ok': false,
            'data': null,
          });

      final user = await repo.checkSession();
      expect(user, isNull);
    });

    test('returns null on network error', () async {
      when(() => api.get(ApiEndpoints.authSession)).thenThrow(Exception('network'));

      final user = await repo.checkSession();
      expect(user, isNull);
    });
  });

  group('login', () {
    test('returns UserModel on success', () async {
      when(() => api.post(ApiEndpoints.authLogin, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'user': {
                    'id': 1,
                    'username': 'admin',
                    'display_name': '管理员',
                    'role': 'admin',
                    'is_active': true,
                    'modules': [],
                  }
                },
              });

      final user = await repo.login('admin', 'admin123');
      expect(user.id, 1);
      verify(() => api.post(ApiEndpoints.authLogin,
          data: {'username': 'admin', 'password': 'admin123'})).called(1);
    });

    test('throws on failure', () async {
      when(() => api.post(ApiEndpoints.authLogin, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': false,
                'error': {'message': '用户名或密码错误'},
              });

      expect(() => repo.login('admin', 'wrong'), throwsException);
    });
  });

  group('logout', () {
    test('calls logout endpoint and clears cookies', () async {
      when(() => api.post(ApiEndpoints.authLogout))
          .thenAnswer((_) async => {'ok': true});
      when(() => api.clearCookies()).thenAnswer((_) async {});

      await repo.logout();

      verify(() => api.post(ApiEndpoints.authLogout)).called(1);
      verify(() => api.clearCookies()).called(1);
    });
  });
}
