import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/patients/data/patient_repository.dart';
import 'package:spine_fupt_app/features/models.dart';
import '../../../helpers/mock_api_client.dart';

final _patientJson = {
  'id': 1,
  'name': '张三',
  'age': 25,
  'sex': 'male',
  'phone': '13800000000',
};

void main() {
  late MockApiClient api;
  late PatientRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = PatientRepository(api);
  });

  group('getPatientsPaginated', () {
    test('returns patients list with pagination info', () async {
      when(() => api.get(ApiEndpoints.patients,
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'items': [_patientJson],
                  'total': 1,
                  'has_more': false,
                },
              });

      final result = await repo.getPatientsPaginated(page: 1, perPage: 20);
      expect(result['total'], 1);
      expect(result['has_more'], false);
      expect(result['items'], isA<List<PatientModel>>());
      expect((result['items'] as List).length, 1);
    });

    test('returns empty on failure', () async {
      when(() => api.get(ApiEndpoints.patients,
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => {'ok': false});

      final result = await repo.getPatientsPaginated();
      expect((result['items'] as List).isEmpty, true);
      expect(result['total'], 0);
    });
  });

  group('createPatient', () {
    test('returns new PatientModel on success', () async {
      when(() => api.post(ApiEndpoints.patients, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {'patient': _patientJson},
              });

      final patient = await repo.createPatient({'name': '张三'});
      expect(patient.id, 1);
      expect(patient.name, '张三');
    });

    test('throws on failure', () async {
      when(() => api.post(ApiEndpoints.patients, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': false,
                'error': {'message': '患者姓名不能为空'},
              });

      expect(() => repo.createPatient({}), throwsException);
    });
  });

  group('getPatientDetail', () {
    test('returns detail map on success', () async {
      when(() => api.get(ApiEndpoints.patient(1))).thenAnswer((_) async => {
            'ok': true,
            'data': {'patient': _patientJson, 'exams': []},
          });

      final detail = await repo.getPatientDetail(1);
      expect(detail['patient'], isNotNull);
    });

    test('throws on failure', () async {
      when(() => api.get(ApiEndpoints.patient(99)))
          .thenAnswer((_) async => {'ok': false});

      expect(() => repo.getPatientDetail(99), throwsException);
    });
  });

  group('updatePatient', () {
    test('succeeds without error', () async {
      when(() => api.patch(ApiEndpoints.patient(1), data: any(named: 'data')))
          .thenAnswer((_) async => {'ok': true});

      await repo.updatePatient(1, {'name': '李四'});
      verify(() => api.patch(ApiEndpoints.patient(1), data: {'name': '李四'}))
          .called(1);
    });
  });

  group('deletePatient', () {
    test('succeeds without error', () async {
      when(() => api.delete(ApiEndpoints.patient(1)))
          .thenAnswer((_) async => {'ok': true});

      await repo.deletePatient(1);
      verify(() => api.delete(ApiEndpoints.patient(1))).called(1);
    });
  });
}
