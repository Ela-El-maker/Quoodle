import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/bootstrap/env.dart';
import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/dio_provider.dart';
import 'package:secure_device_control/core/network/interceptors/auth_interceptor.dart';
import 'package:secure_device_control/core/network/interceptors/logging_interceptor.dart';
import 'package:secure_device_control/core/network/network_info.dart';
import 'package:secure_device_control/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:secure_device_control/core/services/analytics_service.dart';
import 'package:secure_device_control/core/services/crash_reporting_service.dart';
import 'package:secure_device_control/core/services/logger_service.dart';
import 'package:secure_device_control/core/services/push_notification_service.dart';
import 'package:secure_device_control/core/storage/key_value_storage.dart';
import 'package:secure_device_control/core/storage/secure_storage_service.dart';
import 'package:secure_device_control/features/scheduler/data/services/scheduler_service.dart';

final loggerServiceProvider = Provider<LoggerService>((ref) {
  return ConsoleLoggerService();
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return NoOpAnalyticsService();
});

final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  return NoOpCrashReportingService();
});

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return FlutterSecureStorageService(const FlutterSecureStorage());
});

final keyValueStorageProvider = Provider<KeyValueStorage>((ref) {
  return const SharedPrefsStorage();
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnv.controlPlaneBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  dio.interceptors.add(AuthInterceptor(ref.read(secureStorageServiceProvider)));
  dio.interceptors.add(
    TokenRefreshInterceptor(
      dio: dio,
      secureStorage: ref.read(secureStorageServiceProvider),
      logger: ref.read(loggerServiceProvider),
    ),
  );
  dio.interceptors.add(LoggingInterceptor(ref.read(loggerServiceProvider)));
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return DioApiClient(ref.read(dioProvider));
});

final networkInfoProvider = Provider<NetworkInfo>((ref) {
  return NetworkInfo(Connectivity());
});

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService();
});

/// Lazy provider for SchedulerService - initializes on-demand, not at app startup
/// This keeps heavy initialization work off the first frame and improves startup performance
final schedulerServiceProvider =
    FutureProvider.autoDispose<SchedulerService>((ref) async {
  final scheduler = SchedulerService();
  await scheduler.initialize();
  return scheduler;
});
