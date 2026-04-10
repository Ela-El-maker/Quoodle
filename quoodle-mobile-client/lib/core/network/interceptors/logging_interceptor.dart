import 'package:dio/dio.dart';
import 'package:secure_device_control/core/services/logger_service.dart';

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this._logger);

  final LoggerService _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.debug('HTTP ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.error('HTTP ERROR ${err.requestOptions.uri}', error: err);
    handler.next(err);
  }
}
