import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../models.dart';

class ReviewRepository {
  final ApiClient _api;
  ReviewRepository(this._api);

  Future<List<ExamModel>> getReviews() async {
    final res = await _api.get(ApiEndpoints.reviews, queryParameters: {'status': 'all', 'per_page': 50});
    if (res['ok'] == true) {
      final items = res['data']?['items'] as List? ?? res['data'] as List? ?? [];
      return items.map((e) => ExamModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<ExamModel> getReviewDetail(int examId) async {
    final res = await _api.get(ApiEndpoints.review(examId));
    if (res['ok'] == true) {
      final examData = res['data']['exam'] as Map<String, dynamic>? ?? res['data'] as Map<String, dynamic>;
      return ExamModel.fromJson(examData);
    }
    throw Exception('获取复核详情失败');
  }

  Future<void> submitReview(int examId, {required String status, String? reviewNote}) async {
    final res = await _api.post(ApiEndpoints.reviewSubmit(examId), data: {
      'decision': status,
      if (reviewNote != null) 'note': reviewNote,
    });
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '提交复核失败');
    }
  }

  Future<void> deleteReview(int examId) async {
    final res = await _api.delete(ApiEndpoints.review(examId));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '删除失败');
    }
  }

  Future<Map<String, dynamic>> createShareLink(int examId) async {
    final res = await _api.post(ApiEndpoints.reviewShareLink(examId));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('创建分享链接失败');
  }

  Future<List<Map<String, dynamic>>> getShareAccesses(int examId) async {
    final res = await _api.get(ApiEndpoints.reviewShareAccesses(examId));
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getComments(int examId) async {
    final res = await _api.get(ApiEndpoints.reviewComments(examId));
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> addComment(int examId, String content) async {
    final res = await _api.post(ApiEndpoints.reviewComments(examId), data: {
      'content': content,
    });
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('评论失败');
  }

  Future<Map<String, dynamic>> shareToUser(int examId, int toUserId) async {
    final res = await _api.post(ApiEndpoints.reviewShareUser(examId), data: {
      'user_id': toUserId,
    });
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '分享失败');
    }
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> getShareTargets() async {
    final res = await _api.get(ApiEndpoints.shareTargets);
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }
}
