import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_device_control/models/qr_pairing_data.dart';
import 'package:secure_device_control/screens/pairing/pairing_flow_screen.dart';

void main() {
  testWidgets('Pairing flow shows identity and fingerprint', (tester) async {
    final data = QrPairingData(
      type: QrPairingData.expectedType,
      version: QrPairingData.currentVersion,
      deviceId: 'device-123',
      pairToken: 'token-abc',
      pairSessionId: 'sess-1',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      controllerUrl: 'https://example.com',
      deviceLabel: 'Lab Laptop',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PairingFlowScreen(qrData: data),
      ),
    );

    expect(find.text('Confirm device identity'), findsOneWidget);
    expect(find.text('device-123'), findsOneWidget);
    expect(find.text('Fingerprint'), findsOneWidget);
  });
}
