import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../grain/services/local_grain_run_store.dart';

final authStateProvider = FutureProvider<bool>((ref) async {
  const storage = FlutterSecureStorage();
  final accessToken = await storage.read(key: accessTokenKey);
  final refreshToken = await storage.read(key: refreshTokenKey);
  return accessToken != null || refreshToken != null;
});

final guestModeProvider = FutureProvider<bool>((ref) async {
  const storage = FlutterSecureStorage();
  return await storage.read(key: guestModeKey) == 'true';
});

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref),
);

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final _api = ApiClient();
  final _storage = const FlutterSecureStorage();

  AuthNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api
          .post('/auth/login', data: {'email': email, 'password': password});
      await _saveTokens(res.data['data']);
      await _trySyncPendingRuns();
      _ref.invalidate(authStateProvider);
      _ref.invalidate(guestModeProvider);
      await _ref.read(authStateProvider.future);
      await _ref.read(guestModeProvider.future);
      state = const AsyncValue.data(null);
    } on DioException catch (e, st) {
      state = AsyncValue.error(AuthException.fromDio(e), st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.post('/auth/register',
          data: {'name': name, 'email': email, 'password': password});
      await _saveTokens(res.data['data']);
      await _trySyncPendingRuns();
      _ref.invalidate(authStateProvider);
      _ref.invalidate(guestModeProvider);
      await _ref.read(authStateProvider.future);
      await _ref.read(guestModeProvider.future);
      state = const AsyncValue.data(null);
    } on DioException catch (e, st) {
      state = AsyncValue.error(AuthException.fromDio(e), st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Local logout should still complete when the access token is expired.
    }
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: userKey);
    await _storage.delete(key: guestModeKey);
    _ref.invalidate(authStateProvider);
    _ref.invalidate(guestModeProvider);
    await _ref.read(authStateProvider.future);
    await _ref.read(guestModeProvider.future);
  }

  Future<void> continueWithoutLogin() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: userKey);
    await _storage.write(key: guestModeKey, value: 'true');
    _ref.invalidate(authStateProvider);
    _ref.invalidate(guestModeProvider);
    await _ref.read(authStateProvider.future);
    await _ref.read(guestModeProvider.future);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.delete(key: guestModeKey);
    await _storage.write(key: accessTokenKey, value: data['accessToken']);
    await _storage.write(key: refreshTokenKey, value: data['refreshToken']);
    if (data['user'] != null) {
      await _storage.write(key: userKey, value: jsonEncode(data['user']));
    }
  }

  Future<void> _syncPendingRuns() async {
    final store = LocalGrainRunStore();
    final rawUser = await _storage.read(key: userKey);
    if (rawUser == null || rawUser.isEmpty) return;
    final user = jsonDecode(rawUser);
    if (user is! Map) return;
    final userId = user['_id']?.toString() ?? user['id']?.toString() ?? '';
    if (userId.isEmpty) return;
    final pending = await store.claimAndReadPendingForSync(userId);
    if (pending.isEmpty) return;
    await _api.post('/grain/runs/import', data: {'items': pending});
    await store.removePendingForSync(userId);
  }

  Future<void> _trySyncPendingRuns() async {
    try {
      await _syncPendingRuns();
    } catch (_) {
      // Preserve local runs and retry when the signed-in history is refreshed.
    }
  }
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  factory AuthException.fromDio(DioException error) {
    final responseMessage = _responseMessage(error.response?.data);
    if (responseMessage != null && responseMessage.isNotEmpty) {
      return AuthException(responseMessage);
    }

    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'Không kết nối được. Kiểm tra Wi-Fi rồi thử lại.',
      DioExceptionType.connectionError =>
        'Không kết nối được. Kiểm tra kết nối mạng rồi thử lại.',
      DioExceptionType.badResponse when error.response?.statusCode == 401 =>
        'Email hoặc mật khẩu không đúng.',
      DioExceptionType.badResponse =>
        'Đăng nhập thất bại. Vui lòng thử lại sau.',
      _ => 'Đăng nhập thất bại. Vui lòng thử lại.',
    };
    return AuthException(message);
  }

  @override
  String toString() => message;
}

String? _responseMessage(dynamic data) {
  if (data is Map<String, dynamic>) {
    final message = data['message'];
    if (message is String) return message;
  }
  return null;
}
