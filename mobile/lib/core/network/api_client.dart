import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import 'api_base_url_resolver.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  final _baseUrlResolver = ApiBaseUrlResolver();

  // Prevent concurrent refresh attempts (mirrors the web pattern).
  bool _isRefreshing = false;
  final _refreshQueue = <Completer<String?>>[];

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: accessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          try {
            final newToken = await _refreshWithLock();
            if (newToken != null) {
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
              final response = await dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          } catch (_) {}
        }
        return handler.next(error);
      },
    ));
  }

  /// Ensures only one refresh runs at a time. Concurrent callers queue up and
  /// receive the same result once the first refresh completes.
  Future<String?> _refreshWithLock() async {
    if (_isRefreshing) {
      final completer = Completer<String?>();
      _refreshQueue.add(completer);
      return completer.future;
    }
    _isRefreshing = true;
    try {
      final success = await _refresh();
      final token = success ? await _storage.read(key: accessTokenKey) : null;
      for (final c in _refreshQueue) {
        c.complete(token);
      }
      _refreshQueue.clear();
      return token;
    } catch (e) {
      for (final c in _refreshQueue) {
        c.completeError(e);
      }
      _refreshQueue.clear();
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<bool> _refresh() async {
    final refreshToken = await _storage.read(key: refreshTokenKey);
    if (refreshToken == null) return false;
    try {
      final resolvedBaseUrl = await _baseUrlResolver.resolve();
      final response = await Dio().post('$resolvedBaseUrl/auth/refresh',
          data: {'refreshToken': refreshToken});
      final data = response.data['data'];
      await _storage.write(key: accessTokenKey, value: data['accessToken']);
      await _storage.write(key: refreshTokenKey, value: data['refreshToken']);
      return true;
    } on DioException catch (e) {
      // Only if the server explicitly says the refresh token is invalid (401)
      // do we consider it truly expired.  Network errors and 5xx should not
      // wipe the stored tokens so the user can retry when connectivity returns.
      if (e.response?.statusCode == 401) {
        // Refresh token confirmed invalid — clear stored tokens.
        await _storage.delete(key: accessTokenKey);
        await _storage.delete(key: refreshTokenKey);
      }
      return false;
    }
  }

  Future<void> _ensureBaseUrl() async {
    dio.options.baseUrl = await _baseUrlResolver.resolve();
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    await _ensureBaseUrl();
    return dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data, Options? options}) async {
    await _ensureBaseUrl();
    return dio.post(path, data: data, options: options);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    await _ensureBaseUrl();
    return dio.patch(path, data: data);
  }

  Future<Response> delete(String path) async {
    await _ensureBaseUrl();
    return dio.delete(path);
  }
}
