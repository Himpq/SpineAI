import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/questionnaires/data/questionnaire_repository.dart';
import '../../../helpers/mock_api_client.dart';

void main() {
  late MockApiClient api;
  late QuestionnaireRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = QuestionnaireRepository(api);
  });

  group('getQuestionnaires', () {
    test('returns list on success', () async {
      when(() => api.get(ApiEndpoints.questionnaires))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'items': [
                    {'id': 1, 'title': '术后评估'},
                  ],
                },
              });

      final list = await repo.getQuestionnaires();
      expect(list.length, 1);
      expect(list.first['title'], '术后评估');
    });

    test('returns empty on failure', () async {
      when(() => api.get(ApiEndpoints.questionnaires))
          .thenAnswer((_) async => {'ok': false});

      final list = await repo.getQuestionnaires();
      expect(list, isEmpty);
    });
  });

  group('getQuestionnaire', () {
    test('returns detail map', () async {
      when(() => api.get(ApiEndpoints.questionnaire(1)))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'questionnaire': {
                    'id': 1,
                    'title': '术后评估',
                    'questions': [],
                  },
                },
              });

      final q = await repo.getQuestionnaire(1);
      expect(q['id'], 1);
      expect(q['questions'], isA<List>());
    });
  });

  group('createQuestionnaire', () {
    test('returns created questionnaire', () async {
      when(() =>
              api.post(ApiEndpoints.questionnaires, data: any(named: 'data')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'questionnaire': {'id': 2, 'title': '新问卷'},
                },
              });

      final q = await repo.createQuestionnaire({'title': '新问卷', 'questions': []});
      expect(q['id'], 2);
    });
  });

  group('deleteQuestionnaire', () {
    test('succeeds without error', () async {
      when(() => api.delete(ApiEndpoints.questionnaire(1)))
          .thenAnswer((_) async => {'ok': true});

      await repo.deleteQuestionnaire(1);
      verify(() => api.delete(ApiEndpoints.questionnaire(1))).called(1);
    });
  });

  group('stopQuestionnaire', () {
    test('succeeds without error', () async {
      when(() => api.post(ApiEndpoints.questionnaireStop(1)))
          .thenAnswer((_) async => {'ok': true});

      await repo.stopQuestionnaire(1);
      verify(() => api.post(ApiEndpoints.questionnaireStop(1))).called(1);
    });
  });
}
