import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/app/router/app_router.dart';
import 'package:secure_device_control/app/theme/theme_mode_controller.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_providers.dart';
import 'package:secure_device_control/theme/app_theme.dart';
import 'package:sizer/sizer.dart';

class QuoodleApp extends ConsumerStatefulWidget {
  const QuoodleApp({super.key});

  @override
  ConsumerState<QuoodleApp> createState() => _QuoodleAppState();
}

class _QuoodleAppState extends ConsumerState<QuoodleApp> {
  @override
  Widget build(BuildContext context) {
    final notificationService = ref.watch(pushNotificationServiceProvider);
    final authStatus = ref.watch(
      authControllerProvider.select((state) => state.status),
    );
    final themeMode = ref.watch(themeModeControllerProvider);

    AppRouter.updateAuthStatus(authStatus);

    return Sizer(
      builder: (context, orientation, screenType) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final resolvedBrightness = switch (themeMode) {
          ThemeMode.dark => Brightness.dark,
          ThemeMode.light => Brightness.light,
          ThemeMode.system => platformBrightness,
        };
        AppTheme.useBrightness(resolvedBrightness);

        return MaterialApp.router(
          title: 'quoodle',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          routerConfig: AppRouter.goRouter,
          builder: (context, child) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              notificationService.initialize(context);
            });

            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.0),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
