import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../models.dart';
import 'package:dio/dio.dart';
import 'dart:io';

class PatientRepository {
  final ApiClient _api;
  PatientRepository(this._api);

  Future<Map<String, dynamic>> getPatientsPaginated({int page = 1, int perPage = 20, String? search}) async {
    final res = await _api.get(ApiEndpoints.patients, queryParameters: {
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    if (res['ok'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final items = (data['items'] as List? ?? []).map((e) => PatientModel.fromJson(e as Map<String, dynamic>)).toList();
      return {'items': items, 'total': data['total'] ?? 0, 'has_more': data['has_more'] ?? false};
    }
    return {'items': <PatientModel>[], 'total': 0, 'has_more': false};
  }

  Future<List<PatientModel>> getPatients() async {
    final res = await _api.get(ApiEndpoints.patients);
    if (res['ok'] == true) {
      final items = res['data']?['items'] as List? ?? res['data'] as List? ?? [];
      return items.map((e) => PatientModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getPatientDetail(int id) async {
    final res = await _api.get(ApiEndpoints.patient(id));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取患者详情失败');
  }

  Future<PatientModel> createPatient(Map<String, dynamic> data) async {
    final res = await _api.post(ApiEndpoints.patients, data: data);
    if (res['ok'] == true) {
      return PatientModel.fromJson(res['data']['patient'] as Map<String, dynamic>);
    }
    throw Exception(res['error']?['message'] ?? '创建患者失败');
  }

  Future<void> updatePatient(int id, Map<String, dynamic> data) async {
    final res = await _api.patch(ApiEndpoints.patient(id), data: data);
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '更新患者失败');
    }
  }

  Future<void> deletePatient(int id) async {
    final res = await _api.delete(ApiEndpoints.patient(id));
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '删除患者失败');
    }
  }

  Future<Map<String, dynamic>> createRegistrationSession({Map<String, dynamic>? formState}) async {
    final res = await _api.post(ApiEndpoints.registrationSessions, data: {
      if (formState != null) 'form_state': formState,
    });
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('创建登记会话失败');
  }

  Future<Map<String, dynamic>> getRegistrationSession(String token) async {
    final res = await _api.get(ApiEndpoints.registrationSession(token));
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取登记会话失败');
  }

  Future<Map<String, dynamic>> uploadExam(int patientId, File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: imageFile.path.split('/').last),
    });
    final res = await _api.upload(ApiEndpoints.patientExams(patientId), formData);
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['error']?['message'] ?? '上传失败');
  }

  Future<Map<String, dynamic>> createSchedule(Map<String, dynamic> data) async {
    final res = await _api.post(ApiEndpoints.schedules, data: data);
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('创建日程失败');
  }
}
