import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import 'package:dio/dio.dart';

class OverviewRepository {
  final ApiClient _api;
  OverviewRepository(this._api);

  Future<Map<String, dynamic>> getOverview() async {
    try {
      final res = await _api.get(ApiEndpoints.overview);
      if (res['ok'] == true) {
        return res['data'] as Map<String, dynamic>;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('无权限访问总览模块，请联系管理员开通');
      }
      rethrow;
    }
    throw Exception('获取总览失败');
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final res = await _api.get(ApiEndpoints.logs);
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getSystemStatus() async {
    final res = await _api.get(ApiEndpoints.systemStatus);
    if (res['ok'] == true) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception('获取系统状态失败');
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final res = await _api.get(ApiEndpoints.users);
    if (res['ok'] == true) {
      return (res['data']?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<void> createUser(Map<String, dynamic> data) async {
    final res = await _api.post(ApiEndpoints.users, data: data);
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '创建用户失败');
    }
  }

  Future<void> updateUser(int uid, Map<String, dynamic> data) async {
    final res = await _api.patch(ApiEndpoints.user(uid), data: data);
    if (res['ok'] != true) {
      throw Exception(res['error']?['message'] ?? '更新用户失败');
    }
  }
}
