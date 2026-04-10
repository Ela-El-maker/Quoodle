import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secure_device_control/widgets/custom_error_widget.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  _configureErrorWidget();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
}

void _configureErrorWidget() {
  var hasShownError = false;

  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;
      Future.delayed(const Duration(seconds: 5), () {
        hasShownError = false;
      });
      return CustomErrorWidget(errorDetails: details);
    }
    return const SizedBox.shrink();
  };
}
