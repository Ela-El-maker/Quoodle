import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/core/services/logger_service.dart';

class AppRiverpodObserver extends ProviderObserver {
  AppRiverpodObserver(this._logger);

  final LoggerService _logger;

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _logger.debug('Provider updated: ${provider.name ?? provider.runtimeType}');
  }
}
