import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:secure_device_control/app/router/route_names.dart';
import 'package:secure_device_control/app/router/route_paths.dart';
import 'package:secure_device_control/app/router/route_guards.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';
import 'package:secure_device_control/presentation/alerts_screen/alerts_screen.dart';
import 'package:secure_device_control/presentation/analytics_screen/analytics_screen.dart';
import 'package:secure_device_control/presentation/audit_log_screen/audit_log_screen.dart';
import 'package:secure_device_control/presentation/authentication_screen/authentication_screen.dart';
import 'package:secure_device_control/presentation/command_timeline_screen/command_timeline_screen.dart';
import 'package:secure_device_control/presentation/dashboard_screen/dashboard_screen.dart';
import 'package:secure_device_control/presentation/device_detail_screen/device_detail_screen.dart';
import 'package:secure_device_control/presentation/devices_screen/devices_screen.dart';
import 'package:secure_device_control/presentation/notification_center_screen/notification_center_screen.dart';
import 'package:secure_device_control/presentation/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:secure_device_control/presentation/scheduler_screen/scheduler_screen.dart';
import 'package:secure_device_control/presentation/send_command_screen/send_command_screen.dart';
import 'package:secure_device_control/presentation/settings_screen/settings_screen.dart';

class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  static final ValueNotifier<AuthSessionStatus> _authStatusNotifier =
      ValueNotifier<AuthSessionStatus>(AuthSessionStatus.unknown);

  static void updateAuthStatus(AuthSessionStatus status) {
    if (_authStatusNotifier.value != status) {
      _authStatusNotifier.value = status;
    }
  }

  static final GoRouter goRouter = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.initial,
    refreshListenable: _authStatusNotifier,
    redirect: (_, state) => RouteGuards.authRedirect(
      authStatus: _authStatusNotifier.value,
      location: state.matchedLocation,
    ),
    routes: [
      _route(
        name: RouteNames.initial,
        path: RoutePaths.initial,
        builder: () => const AuthenticationScreen(),
      ),
      _route(
        name: RouteNames.authentication,
        path: RoutePaths.authentication,
        builder: () => const AuthenticationScreen(),
      ),
      _route(
        name: RouteNames.dashboard,
        path: RoutePaths.dashboard,
        builder: () => const DashboardScreen(),
      ),
      _route(
        name: RouteNames.devices,
        path: RoutePaths.devices,
        builder: () => const DevicesScreen(),
      ),
      _route(
        name: RouteNames.deviceDetail,
        path: RoutePaths.deviceDetail,
        builder: () => const DeviceDetailScreen(),
      ),
      _route(
        name: RouteNames.commandTimeline,
        path: RoutePaths.commandTimeline,
        builder: () => const CommandTimelineScreen(),
      ),
      _route(
        name: RouteNames.alerts,
        path: RoutePaths.alerts,
        builder: () => const AlertsScreen(),
      ),
      _route(
        name: RouteNames.qrScanner,
        path: RoutePaths.qrScanner,
        builder: () => const QrScannerScreen(),
      ),
      _route(
        name: RouteNames.sendCommand,
        path: RoutePaths.sendCommand,
        builder: () => const SendCommandScreen(),
      ),
      _route(
        name: RouteNames.settings,
        path: RoutePaths.settings,
        builder: () => const SettingsScreen(),
      ),
      _route(
        name: RouteNames.scheduler,
        path: RoutePaths.scheduler,
        builder: () => const SchedulerScreen(),
      ),
      _route(
        name: RouteNames.notificationCenter,
        path: RoutePaths.notificationCenter,
        builder: () => const NotificationCenterScreen(),
      ),
      _route(
        name: RouteNames.auditLog,
        path: RoutePaths.auditLog,
        builder: () => const AuditLogScreen(),
      ),
      _route(
        name: RouteNames.analytics,
        path: RoutePaths.analytics,
        builder: () => const AnalyticsScreen(),
      ),
    ],
  );

  static GoRoute _route({
    required String name,
    required String path,
    required Widget Function() builder,
  }) {
    return GoRoute(
      name: name,
      path: path,
      pageBuilder: (_, state) => MaterialPage<void>(
        name: path,
        arguments: state.extra,
        child: builder(),
      ),
    );
  }
}
