import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spine_fupt_app/core/api/api_endpoints.dart';
import 'package:spine_fupt_app/features/reviews/data/review_repository.dart';
import 'package:spine_fupt_app/features/models.dart';
import '../../../helpers/mock_api_client.dart';

final _examJson = {
  'id': 10,
  'patient_id': 1,
  'patient_name': '张三',
  'status': 'pending_review',
  'spine_class': 'lumbar',
  'created_at': '2025-01-01T00:00:00Z',
};

void main() {
  late MockApiClient api;
  late ReviewRepository repo;

  setUp(() {
    api = MockApiClient();
    repo = ReviewRepository(api);
  });

  group('getReviews', () {
    test('returns list of ExamModel', () async {
      when(() => api.get(ApiEndpoints.reviews,
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => {
                'ok': true,
                'data': {
                  'items': [_examJson],
                },
              });

      final reviews = await repo.getReviews();
      expect(reviews.length, 1);
      expect(reviews.first.id, 10);
      expect(reviews.first.isLumbar, true);
    });

    test('returns empty list on failure', () async {
      when(() => api.get(ApiEndpoints.reviews,
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async => {'ok': false});

      final reviews = await repo.getReviews();
      expect(reviews, isEmpty);
    });
  });

  group('getReviewDetail', () {
    test('returns ExamModel on success', () async {
      when(() => api.get(ApiEndpoints.review(10))).thenAnswer((_) async => {
            'ok': true,
            'data': {'exam': _examJson},
          });

      final exam = await repo.getReviewDetail(10);
      expect(exam.id, 10);
      expect(exam.patientName, '张三');
    });
  });

  group('submitReview', () {
    test('calls endpoint with correct data', () async {
      when(() => api.post(ApiEndpoints.reviewSubmit(10),
              data: any(named: 'data')))
          .thenAnswer((_) async => {'ok': true});

      await repo.submitReview(10, status: 'reviewed', reviewNote: 'OK');
      verify(() => api.post(ApiEndpoints.reviewSubmit(10),
          data: {'decision': 'reviewed', 'note': 'OK'})).called(1);
    });
  });

  group('deleteReview', () {
    test('succeeds without error', () async {
      when(() => api.delete(ApiEndpoints.review(10)))
          .thenAnswer((_) async => {'ok': true});

      await repo.deleteReview(10);
      verify(() => api.delete(ApiEndpoints.review(10))).called(1);
    });
  });
}
