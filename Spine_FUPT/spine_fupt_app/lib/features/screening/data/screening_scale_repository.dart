import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';

class ScreeningScaleRepository {
  final _api = ApiClient.instance;

  // ─── Doctor endpoints ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getScales() async {
    final resp = await _api.get(ApiEndpoints.screeningScales);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }

  Future<Map<String, dynamic>> getScale(int id) async {
    final resp = await _api.get(ApiEndpoints.screeningScale(id));
    return Map<String, dynamic>.from(resp['data'] ?? {});
  }

  Future<Map<String, dynamic>> createScale(Map<String, dynamic> data) async {
    final resp = await _api.post(ApiEndpoints.screeningScales, data: data);
    return Map<String, dynamic>.from(resp['data'] ?? {});
  }

  Future<Map<String, dynamic>> updateScale(int id, Map<String, dynamic> data) async {
    final resp = await _api.put(ApiEndpoints.screeningScale(id), data: data);
    return Map<String, dynamic>.from(resp['data'] ?? {});
  }

  Future<void> deleteScale(int id) async {
    await _api.delete(ApiEndpoints.screeningScale(id));
  }

  // ─── Public endpoints ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPublicScales() async {
    final resp = await _api.get(ApiEndpoints.publicScreeningScales);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }
}
