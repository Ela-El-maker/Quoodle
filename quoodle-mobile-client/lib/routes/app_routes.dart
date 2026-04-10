import 'package:flutter/material.dart';
import 'package:secure_device_control/app/router/route_paths.dart';

class AppRoutes {
  static const String initial = RoutePaths.initial;
  static const String authenticationScreen = RoutePaths.authentication;
  static const String dashboardScreen = RoutePaths.dashboard;
  static const String devicesScreen = RoutePaths.devices;
  static const String deviceDetailScreen = RoutePaths.deviceDetail;
  static const String commandTimelineScreen = RoutePaths.commandTimeline;
  static const String alertsScreen = RoutePaths.alerts;
  static const String qrScannerScreen = RoutePaths.qrScanner;
  static const String sendCommandScreen = RoutePaths.sendCommand;
  static const String settingsScreen = RoutePaths.settings;
  static const String schedulerScreen = RoutePaths.scheduler;
  static const String notificationCenterScreen = RoutePaths.notificationCenter;
  static const String auditLogScreen = RoutePaths.auditLog;
  static const String analyticsScreen = RoutePaths.analytics;

  @Deprecated(
    'Named-route map is retired. Use AppNavigator/AppRouter with GoRouter.',
  )
  static const Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{};

  @Deprecated(
    'onGenerateRoute compatibility is retired. Use AppNavigator/AppRouter.',
  )
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) => null;
}
