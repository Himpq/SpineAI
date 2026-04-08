import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/overview/data/overview_repository.dart';
import '../../../helpers/mock_api_client.dart';

void main() {
  late MockApiClient api;
  late OverviewRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = OverviewRepository(api);
  });

  group('getOverview', () {
    test('returns data map on success', () async {
      when(() => api.get(ApiEndpoints.overview)).thenAnswer((_) async => {
            'ok': true,
            'data': {
              'stats': {'patients': 10, 'exams': 5},
            },
          });

      final result = await repo.getOverview();
      expect(result['stats'], isNotNull);
    });

    test('throws on failure', () async {
      when(() => api.get(ApiEndpoints.overview))
          .thenAnswer((_) async => {'ok': false});

      expect(() => repo.getOverview(), throwsException);
    });
  });

  group('getLogs', () {
    test('returns list of logs', () async {
      when(() => api.get(ApiEndpoints.logs)).thenAnswer((_) async => {
            'ok': true,
            'data': {
              'items': [
                {'id': 1, 'action': 'login'}
              ],
            },
          });

      final logs = await repo.getLogs();
      expect(logs.length, 1);
    });
  });

  group('getSystemStatus', () {
    test('returns status map', () async {
      when(() => api.get(ApiEndpoints.systemStatus))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {'version': '1.0', 'uptime': 3600},
              });

      final status = await repo.getSystemStatus();
      expect(status['version'], '1.0');
    });
  });

  group('createUser', () {
    test('succeeds without error', () async {
      when(() => api.post(ApiEndpoints.users, data: any(named: 'data')))
          .thenAnswer((_) async => {'ok': true});

      await repo.createUser({'username': 'doc1', 'password': '123456', 'role': 'doctor'});
      verify(() => api.post(ApiEndpoints.users, data: any(named: 'data')))
          .called(1);
    });

    test('throws on failure', () async {
      when(() => api.post(ApiEndpoints.users, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': false,
                'error': {'message': '用户名已存在'},
              });

      expect(
          () => repo.createUser({'username': 'dup'}), throwsException);
    });
  });
}
