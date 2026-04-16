import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import 'package:dio/dio.dart';
import 'dart:io';

class PortalRepository {
  final ApiClient _api;
  PortalRepository(this._api);

  Future<Map<String, dynamic>> getPortalData(String token) async {
    final res = await _api.get(ApiEndpoints.publicPortal(token));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取患者信息失败');
  }

  Future<Map<String, dynamic>> getPortalChat(String token) async {
    final res = await _api.get(ApiEndpoints.publicPortalChat(token));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取聊天记录失败');
  }

  Future<void> sendMessage(String token, String content) async {
    final res = await _api.post(ApiEndpoints.publicPortalMessages(token), data: {
      'content': content,
    });
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '发送失败');
    }
  }

  Future<Map<String, dynamic>> uploadExam(String token, File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: imageFile.path.split('/').last),
    });
    final res = await _api.upload(ApiEndpoints.publicPortalExams(token), formData);
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['error']?['message'] ?? '上传失败');
  }

  Future<void> deleteExam(String token, int examId) async {
    final res = await _api.delete(ApiEndpoints.publicPortalExam(token, examId));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '删除失败');
    }
  }

  // Public case
  Future<Map<String, dynamic>> getPublicCase(String token) async {
    final res = await _api.get(ApiEndpoints.publicCase(token));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取病例失败');
  }

  Future<void> addPublicComment(String token, {required String content, String authorName = '访客'}) async {
    final res = await _api.post(ApiEndpoints.publicCaseComments(token), data: {
      'content': content,
      'author_name': authorName,
    });
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '评论失败');
    }
  }

  // Public questionnaire
  Future<Map<String, dynamic>> getPublicQuestionnaire(String token) async {
    final res = await _api.get(ApiEndpoints.publicQuestionnaire(token));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取问卷失败');
  }

  Future<void> submitQuestionnaire(String token, Map<String, dynamic> answers) async {
    final res = await _api.post(ApiEndpoints.publicQuestionnaireSubmit(token), data: answers);
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '提交失败');
    }
  }
}
