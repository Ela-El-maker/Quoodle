import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/app.dart';
import 'package:secure_device_control/app/bootstrap/app_observer.dart';
import 'package:secure_device_control/app/bootstrap/bootstrap.dart';
import 'package:secure_device_control/core/services/logger_service.dart';

Future<void> main() async {
  await bootstrap();

  runApp(
    ProviderScope(
      observers: [AppRiverpodObserver(ConsoleLoggerService())],
      child: QuoodleApp(),
    ),
  );
}
