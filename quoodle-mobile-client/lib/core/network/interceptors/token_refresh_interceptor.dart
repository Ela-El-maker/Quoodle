import 'package:dio/dio.dart';
import 'package:secure_device_control/core/network/endpoints.dart';
import 'package:secure_device_control/core/services/logger_service.dart';
import 'package:secure_device_control/core/storage/secure_storage_service.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';

class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required Dio dio,
    required SecureStorageService secureStorage,
    required LoggerService logger,
  })  : _dio = dio,
        _secureStorage = secureStorage,
        _logger = logger;

  final Dio _dio;
  final SecureStorageService _secureStorage;
  final LoggerService _logger;

  Future<String?>? _ongoingRefresh;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final requestOptions = err.requestOptions;

    if (statusCode != 401 ||
        _isRefreshRequest(requestOptions.path) ||
        requestOptions.extra['skip_auth_refresh'] == true ||
        requestOptions.extra['retried_after_refresh'] == true) {
      handler.next(err);
      return;
    }

    final refreshToken = await _secureStorage.read(StorageKeys.refreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      handler.next(err);
      return;
    }

    try {
      final newToken = await _refreshAccessToken(refreshToken);
      if (newToken == null || newToken.isEmpty) {
        handler.next(err);
        return;
      }

      final headers = Map<String, dynamic>.from(requestOptions.headers);
      headers['Authorization'] = 'Bearer $newToken';

      final retriedResponse = await _dio.fetch<dynamic>(
        requestOptions.copyWith(
          headers: headers,
          extra: <String, dynamic>{
            ...requestOptions.extra,
            'retried_after_refresh': true,
          },
        ),
      );

      handler.resolve(retriedResponse);
    } catch (refreshError, stackTrace) {
      _logger.error(
        'Token refresh failed',
        error: refreshError,
        stackTrace: stackTrace,
      );
      handler.next(err);
    }
  }

  bool _isRefreshRequest(String path) {
    return path == Endpoints.refreshSession ||
        path.endsWith(Endpoints.refreshSession);
  }

  Future<String?> _refreshAccessToken(String refreshToken) async {
    _ongoingRefresh ??= _performTokenRefresh(refreshToken);
    try {
      return await _ongoingRefresh;
    } finally {
      _ongoingRefresh = null;
    }
  }

  Future<String?> _performTokenRefresh(String refreshToken) async {
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
      ),
    );

    final response = await refreshDio.post<Map<String, dynamic>>(
      Endpoints.refreshSession,
      data: <String, dynamic>{'refresh_token': refreshToken},
      options: Options(extra: const {'skip_auth_refresh': true}),
    );

    final payload = response.data ?? const <String, dynamic>{};
    final jwt = payload['jwt'] as String? ?? '';
    final newRefreshToken = payload['refresh_token'] as String? ?? '';
    if (jwt.isEmpty || newRefreshToken.isEmpty) {
      return null;
    }

    await _secureStorage.write(StorageKeys.authToken, jwt);
    await _secureStorage.write(StorageKeys.refreshToken, newRefreshToken);
    return jwt;
  }
}
