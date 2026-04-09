import 'package:flutter/material.dart';
import '../presentation/authentication_screen/authentication_screen.dart';
import '../presentation/dashboard_screen/dashboard_screen.dart';
import '../presentation/devices_screen/devices_screen.dart';
import '../presentation/device_detail_screen/device_detail_screen.dart';
import '../presentation/command_timeline_screen/command_timeline_screen.dart';
import '../presentation/alerts_screen/alerts_screen.dart';
import '../presentation/qr_scanner_screen/qr_scanner_screen.dart';
import '../presentation/send_command_screen/send_command_screen.dart';
import '../presentation/settings_screen/settings_screen.dart';
import '../presentation/scheduler_screen/scheduler_screen.dart';
import '../presentation/notification_center_screen/notification_center_screen.dart';
import '../presentation/audit_log_screen/audit_log_screen.dart';
import '../presentation/analytics_screen/analytics_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String authenticationScreen = '/authentication-screen';
  static const String dashboardScreen = '/dashboard-screen';
  static const String devicesScreen = '/devices-screen';
  static const String deviceDetailScreen = '/device-detail-screen';
  static const String commandTimelineScreen = '/command-timeline-screen';
  static const String alertsScreen = '/alerts-screen';
  static const String qrScannerScreen = '/qr-scanner-screen';
  static const String sendCommandScreen = '/send-command-screen';
  static const String settingsScreen = '/settings-screen';
  static const String schedulerScreen = '/scheduler-screen';
  static const String notificationCenterScreen = '/notification-center-screen';
  static const String auditLogScreen = '/audit-log-screen';
  static const String analyticsScreen = '/analytics-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const AuthenticationScreen(),
    authenticationScreen: (context) => const AuthenticationScreen(),
    dashboardScreen: (context) => const DashboardScreen(),
    devicesScreen: (context) => const DevicesScreen(),
    deviceDetailScreen: (context) => const DeviceDetailScreen(),
    commandTimelineScreen: (context) => const CommandTimelineScreen(),
    alertsScreen: (context) => const AlertsScreen(),
    qrScannerScreen: (context) => const QrScannerScreen(),
    sendCommandScreen: (context) => const SendCommandScreen(),
    settingsScreen: (context) => const SettingsScreen(),
    schedulerScreen: (context) => const SchedulerScreen(),
    notificationCenterScreen: (context) => const NotificationCenterScreen(),
    auditLogScreen: (context) => const AuditLogScreen(),
    analyticsScreen: (context) => const AnalyticsScreen(),
  };
}
