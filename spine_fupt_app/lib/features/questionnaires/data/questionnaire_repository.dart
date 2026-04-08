import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';

class QuestionnaireRepository {
  final ApiClient _api;
  QuestionnaireRepository(this._api);

  Future<List<Map<String, dynamic>>> getQuestionnaires() async {
    final res = await _api.get(ApiEndpoints.questionnaires);
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getQuestionnaire(int qid) async {
    final res = await _api.get(ApiEndpoints.questionnaire(qid));
    if (res['ok'] == true) {
      return res['data']['questionnaire'] as Map<String, dynamic>;
    }
    throw Exception('获取问卷详情失败');
  }

  Future<Map<String, dynamic>> createQuestionnaire(Map<String, dynamic> data) async {
    final res = await _api.post(ApiEndpoints.questionnaires, data: data);
    if (res['ok'] == true) return res['data']['questionnaire'] as Map<String, dynamic>;
    throw Exception(res['error']?['message'] ?? '创建失败');
  }

  Future<Map<String, dynamic>> updateQuestionnaire(int qid, Map<String, dynamic> data) async {
    final res = await _api.put(ApiEndpoints.questionnaire(qid), data: data);
    if (res['ok'] == true) return res['data']['questionnaire'] as Map<String, dynamic>;
    throw Exception(res['error']?['message'] ?? '更新失败');
  }

  Future<void> safeEditQuestionnaire(int qid, Map<String, dynamic> data) async {
    final res = await _api.patch(ApiEndpoints.questionnaireSafeEdit(qid), data: data);
    if (res['ok'] != true) throw Exception(res['error']?['message'] ?? '安全编辑失败');
  }

  Future<void> deleteQuestionnaire(int qid) async {
    final res = await _api.delete(ApiEndpoints.questionnaire(qid));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '删除失败');
    }
  }

  Future<void> stopQuestionnaire(int qid) async {
    final res = await _api.post(ApiEndpoints.questionnaireStop(qid));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '终止失败');
    }
  }

  Future<List<Map<String, dynamic>>> assignQuestionnaire(int qid, List<int> patientIds) async {
    final res = await _api.post(ApiEndpoints.questionnaireAssign(qid), data: {
      'patient_ids': patientIds,
    });
    if (res['ok'] == true) {
      return (res['data']?['assignments'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    throw Exception(res['error']?['message'] ?? '发送失败');
  }

  Future<Map<String, dynamic>> getResponses(int qid) async {
    final res = await _api.get(ApiEndpoints.questionnaireResponses(qid));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取回收数据失败');
  }

  Future<Map<String, dynamic>> getResponseDetail(int qid, int rid) async {
    final res = await _api.get(ApiEndpoints.questionnaireResponse(qid, rid));
    if (res['ok'] == true) {
      return res['data']['response'] as Map<String, dynamic>;
    }
    throw Exception('获取回收详情失败');
  }

  Future<void> deleteResponse(int qid, int rid) async {
    final res = await _api.delete(ApiEndpoints.questionnaireResponse(qid, rid));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '删除失败');
    }
  }
}
