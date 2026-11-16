import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../security/secure_vault_storage.dart';

class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => message;
}

/// Configured Dio client enforcing HTTPS, Bearer JWT injection, and single-flight
/// Refresh Token rotation on HTTP 401 so users never pay extra SMS costs unnecessarily.
class ApiClient {
  final Dio dio;
  final SecureVaultStorage _vaultStorage;
  final void Function() onSessionExpired;
  Completer<bool>? _refreshCompleter;

  ApiClient({
    required this.dio,
    required SecureVaultStorage vaultStorage,
    required this.onSessionExpired,
  }) : _vaultStorage = vaultStorage {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final isAuthlessEndpoint = options.path.startsWith('/auth/send-otp') ||
              options.path.startsWith('/auth/verify-otp') ||
              options.path.startsWith('/auth/refresh');

          if (!isAuthlessEndpoint) {
            final accessToken = await _vaultStorage.getAccessToken();
            if (accessToken != null && accessToken.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $accessToken';
            }
          }
          handler.next(options);
        },
        onError: (DioException error, handler) async {
          final statusCode = error.response?.statusCode;
          final requestPath = error.requestOptions.path;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (statusCode == 401 &&
              !alreadyRetried &&
              !requestPath.startsWith('/auth/')) {
            final refreshed = await _tryRefreshSessionSingleFlight();
            if (refreshed) {
              final newAccessToken = await _vaultStorage.getAccessToken();
              final retryOptions = error.requestOptions;
              retryOptions.extra['retried'] = true;
              retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
              try {
                final response = await dio.fetch<dynamic>(retryOptions);
                return handler.resolve(response);
              } on DioException catch (retryErr) {
                return handler.next(retryErr);
              }
            } else {
              onSessionExpired();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<bool> _tryRefreshSessionSingleFlight() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await _vaultStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      final refreshDio = Dio(BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));

      final res = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final data = res.data?['data'] as Map<String, dynamic>?;
      if (data == null) {
        completer.complete(false);
        return false;
      }

      final user = data['user'] as Map<String, dynamic>;
      await _vaultStorage.saveSession(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        userId: user['id'] as String,
        phoneMasked: user['phoneMasked'] as String,
        preferredLang: user['preferredLang'] as String,
      );

      completer.complete(true);
      return true;
    } catch (_) {
      await _vaultStorage.wipeAllSessionAndDrmKeys();
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  static ApiException mapDioError(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final errObj = data['error'] as Map<String, dynamic>;
        return ApiException(
          code: (errObj['code'] ?? 'API_ERROR').toString(),
          message: (errObj['message'] ?? 'Request failed').toString(),
          statusCode: error.response?.statusCode,
        );
      }
      return ApiException(
        code: 'NETWORK_ERROR',
        message: 'Network connection error. Please check your internet connection.',
        statusCode: error.response?.statusCode,
      );
    }
    return ApiException(
      code: 'UNKNOWN_ERROR',
      message: error.toString(),
    );
  }
}

/// Session Forced-Logout Signal Stream so GoRouter redirects cleanly on token revocation.
final sessionInvalidatedCounterProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>((ref) {
  final vaultStorage = ref.watch(secureVaultStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  return ApiClient(
    dio: dio,
    vaultStorage: vaultStorage,
    onSessionExpired: () {
      ref.read(sessionInvalidatedCounterProvider.notifier).state++;
    },
  );
});
