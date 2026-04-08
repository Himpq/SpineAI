import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class ApiClient {
  static ApiClient? _instance;
  late Dio dio;
  late PersistCookieJar _cookieJar;
  String baseUrl;
  /// Called when any request receives 401; use to trigger logout in the UI layer.
  void Function()? onUnauthorized;

  ApiClient._internal(this.baseUrl);

  static Future<ApiClient> getInstance({String? baseUrl}) async {
    if (_instance == null) {
      _instance = ApiClient._internal(baseUrl ?? 'http://192.168.1.112:5000');
      await _instance!._init();
    }
    return _instance!;
  }

  static ApiClient get instance {
    assert(_instance != null, 'ApiClient not initialized. Call getInstance() first.');
    return _instance!;
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(CookieManager(_cookieJar));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint('[API] $o'),
      ));
    }
    // Auto-detect session expiry (skip auth endpoints — login 401 is expected)
    dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) {
        final path = e.requestOptions.path;
        if (e.response?.statusCode == 401 &&
            onUnauthorized != null &&
            !path.startsWith('/api/auth/')) {
          onUnauthorized!();
        }
        handler.next(e);
      },
    ));
    // Auto-retry GET requests on transient network failures (once)
    dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) async {
        if (_isRetryable(e) &&
            e.requestOptions.method == 'GET' &&
            e.requestOptions.extra['_retried'] != true) {
          e.requestOptions.extra['_retried'] = true;
          await Future.delayed(const Duration(seconds: 2));
          try {
            final response = await dio.fetch(e.requestOptions);
            return handler.resolve(response);
          } catch (_) {}
        }
        handler.next(e);
      },
    ));
  }

  static bool _isRetryable(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  void updateBaseUrl(String newBaseUrl) {
    baseUrl = newBaseUrl;
    dio.options.baseUrl = newBaseUrl;
  }

  Future<void> clearCookies() async {
    await _cookieJar.deleteAll();
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters}) async {
    final response = await dio.get(path, queryParameters: queryParameters);
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    final response = await dio.post(path, data: data, queryParameters: queryParameters);
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    final response = await dio.patch(path, data: data);
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    final response = await dio.put(path, data: data);
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await dio.delete(path);
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> upload(String path, FormData formData, {void Function(int, int)? onSendProgress}) async {
    final response = await dio.post(
      path,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: onSendProgress,
    );
    return _parseResponse(response);
  }

  Map<String, dynamic> _parseResponse(Response response) {
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    return {'ok': true, 'data': response.data};
  }

  String getFullUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  /// Convert a DioException or generic error into a user-friendly Chinese message.
  static String friendlyError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '网络连接超时，请检查网络后重试';
        case DioExceptionType.connectionError:
          return '无法连接到服务器，请检查网络设置';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          var body = error.response?.data;
          // If Dio returned a raw JSON string, try to decode it
          if (body is String) {
            try { body = jsonDecode(body); } catch (_) {}
          }
          if (body is Map && body['error'] is Map) {
            final msg = body['error']['message'];
            if (msg is String && msg.isNotEmpty) return msg;
          }
          if (statusCode == 403) return '无权限执行此操作';
          if (statusCode == 404) return '请求的资源不存在';
          if (statusCode == 500) return '服务器内部错误，请稍后重试';
          return '请求失败 ($statusCode)';
        case DioExceptionType.cancel:
          return '请求已取消';
        default:
          return '网络异常，请稍后重试';
      }
    }
    final msg = error.toString();
    // Strip "Exception: " prefix for cleaner display
    if (msg.startsWith('Exception: ')) return msg.substring(11);
    return msg;
  }
}
