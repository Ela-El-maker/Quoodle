import 'package:flutter/material.dart';

import 'screens/auth/login_screen.dart';
import 'screens/devices/device_list_screen.dart';
import 'screens/pairing/qr_scan_screen.dart';

void main() {
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
      initialRoute: LoginScreen.route,
      routes: {
        LoginScreen.route: (_) => const LoginScreen(),
        DeviceListScreen.route: (_) => const DeviceListScreen(),
        QrScanScreen.route: (_) => const QrScanScreen(),
      },
    );
  }
}
