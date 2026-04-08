import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/user_model.dart';

class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  Future<UserModel?> checkSession() async {
    try {
      final res = await _api.get(ApiEndpoints.authSession);
      if (res['ok'] == true && res['data'] != null && res['data']['user'] != null) {
        return UserModel.fromJson(res['data']['user'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<UserModel> login(String username, String password) async {
    final res = await _api.post(ApiEndpoints.authLogin, data: {
      'username': username,
      'password': password,
    });
    if (res['ok'] == true) {
      return UserModel.fromJson(res['data']['user'] as Map<String, dynamic>);
    }
    throw Exception(res['error']?['message'] ?? '登录失败');
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiEndpoints.authLogout);
    } catch (_) {}
    await _api.clearCookies();
  }
}
