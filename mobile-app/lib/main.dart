import 'package:flutter/material.dart';

import 'services/mobile_identity_service.dart';
import 'services/session_store.dart';
import 'screens/alerts/alerts_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/twofa_screen.dart';
import 'screens/commands/send_command_screen.dart';
import 'screens/devices/device_detail_screen.dart';
import 'screens/devices/device_list_screen.dart';
import 'screens/pairing/qr_scan_screen.dart';
import 'screens/telemetry/telemetry_view.dart';
import 'screens/updates/update_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionStore.init();
  await MobileIdentityService().ensureKeypair();
  runApp(const SecureDeviceApp());
}

class SecureDeviceApp extends StatelessWidget {
  const SecureDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Device Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      initialRoute:
          SessionStore.isLoggedIn ? DeviceListScreen.route : LoginScreen.route,
      routes: {
        LoginScreen.route: (_) => const LoginScreen(),
        RegisterScreen.route: (_) => const RegisterScreen(),
        DeviceListScreen.route: (_) => const DeviceListScreen(),
        QrScanScreen.route: (_) => const QrScanScreen(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case TwoFAScreen.route:
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (_) => TwoFAScreen(
                userId: args['user_id'] as String? ?? '',
                sessionId: args['session_id'] as String? ?? '',
              ),
            );
          case DeviceDetailScreen.route:
            final deviceId = (settings.arguments
                    as Map<String, dynamic>?)?['device_id'] as String? ??
                '';
            return MaterialPageRoute(
                builder: (_) => DeviceDetailScreen(deviceId: deviceId));
          case SendCommandScreen.route:
            final deviceId = (settings.arguments
                    as Map<String, dynamic>?)?['device_id'] as String? ??
                '';
            return MaterialPageRoute(
                builder: (_) => SendCommandScreen(deviceId: deviceId));
          case TelemetryViewScreen.route:
            final deviceId = (settings.arguments
                    as Map<String, dynamic>?)?['device_id'] as String? ??
                '';
            return MaterialPageRoute(
                builder: (_) => TelemetryViewScreen(deviceId: deviceId));
          case AlertsScreen.route:
            final deviceId = (settings.arguments
                    as Map<String, dynamic>?)?['device_id'] as String? ??
                '';
            return MaterialPageRoute(
                builder: (_) => AlertsScreen(deviceId: deviceId));
          case UpdateListScreen.route:
            final deviceId = (settings.arguments
                    as Map<String, dynamic>?)?['device_id'] as String? ??
                '';
            return MaterialPageRoute(
                builder: (_) => UpdateListScreen(deviceId: deviceId));
        }
        return null;
      },
    );
  }
}
