import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/models/qr_pairing_data.dart';

void main() {
  test('QrPairingData exposes expectedType and supportedVersion', () {
    expect(QrPairingData.expectedType, 'quoodle_pair');
    expect(QrPairingData.supportedVersion, 1);
  });
}
