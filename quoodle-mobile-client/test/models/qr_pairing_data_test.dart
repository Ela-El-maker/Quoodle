import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/models/qr_pairing_data.dart';

void main() {
  group('QrPairingData', () {
    String validQrJson({
      String type = 'quoodle_pair',
      int version = 1,
      String deviceId = 'TEST-001',
      String pairToken = 'test-token-123',
      String pairSessionId = 'sess-test-456',
      String? timestamp,
      String? controllerUrl,
      String? deviceLabel,
    }) {
      final ts = timestamp ?? DateTime.now().toUtc().toIso8601String();
      final data = {
        'type': type,
        'version': version,
        'device_id': deviceId,
        'pair_token': pairToken,
        'pair_session_id': pairSessionId,
        'timestamp': ts,
        if (controllerUrl != null) 'controller_url': controllerUrl,
        if (deviceLabel != null) 'device_label': deviceLabel,
      };
      return jsonEncode(data);
    }

    test('parses valid QR code data', () {
      final raw = validQrJson();
      final data = QrPairingData.fromRawString(raw);

      expect(data.type, 'quoodle_pair');
      expect(data.version, 1);
      expect(data.deviceId, 'TEST-001');
      expect(data.pairToken, 'test-token-123');
      expect(data.pairSessionId, 'sess-test-456');
    });

    test('parses optional fields', () {
      final raw = validQrJson(
        controllerUrl: 'https://api.example.com',
        deviceLabel: 'My Device',
      );
      final data = QrPairingData.fromRawString(raw);

      expect(data.controllerUrl, 'https://api.example.com');
      expect(data.deviceLabel, 'My Device');
    });

    test('throws on empty string', () {
      expect(
        () => QrPairingData.fromRawString(''),
        throwsA(isA<QrParseException>()),
      );
    });

    test('throws on invalid JSON', () {
      expect(
        () => QrPairingData.fromRawString('not json'),
        throwsA(isA<QrParseException>()),
      );
    });

    test('throws on wrong type', () {
      final raw = validQrJson(type: 'wrong_type');
      expect(
        () => QrPairingData.fromRawString(raw),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('Invalid QR type'),
          ),
        ),
      );
    });

    test('throws on unsupported version', () {
      final raw = validQrJson(version: 999);
      expect(
        () => QrPairingData.fromRawString(raw),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported QR version'),
          ),
        ),
      );
    });

    test('throws on missing device_id', () {
      final data = {
        'type': 'quoodle_pair',
        'version': 1,
        'pair_token': 'token',
        'pair_session_id': 'sess',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      expect(
        () => QrPairingData.fromRawString(jsonEncode(data)),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('device_id'),
          ),
        ),
      );
    });

    test('throws on missing pair_token', () {
      final data = {
        'type': 'quoodle_pair',
        'version': 1,
        'device_id': 'TEST-001',
        'pair_session_id': 'sess',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      expect(
        () => QrPairingData.fromRawString(jsonEncode(data)),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('pair_token'),
          ),
        ),
      );
    });

    test('throws on expired timestamp', () {
      final oldTimestamp = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      final raw = validQrJson(timestamp: oldTimestamp);

      expect(
        () => QrPairingData.fromRawString(raw),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('throws on future timestamp', () {
      final futureTimestamp = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String();
      final raw = validQrJson(timestamp: futureTimestamp);

      expect(
        () => QrPairingData.fromRawString(raw),
        throwsA(
          isA<QrParseException>().having(
            (e) => e.message,
            'message',
            contains('future'),
          ),
        ),
      );
    });

    test('accepts timestamp within tolerance', () {
      // 2 minutes ago should be fine
      final recentTimestamp = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 2))
          .toIso8601String();
      final raw = validQrJson(timestamp: recentTimestamp);

      final data = QrPairingData.fromRawString(raw);
      expect(data.deviceId, 'TEST-001');
    });

    test('toJson roundtrip', () {
      final original = QrPairingData(
        type: 'quoodle_pair',
        version: 1,
        deviceId: 'TEST-001',
        pairToken: 'token-abc',
        pairSessionId: 'sess-xyz',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        controllerUrl: 'https://api.example.com',
        deviceLabel: 'Test Device',
      );

      final json = original.toJson();
      final restored = QrPairingData.fromJson(json);

      expect(restored.type, original.type);
      expect(restored.version, original.version);
      expect(restored.deviceId, original.deviceId);
      expect(restored.pairToken, original.pairToken);
      expect(restored.pairSessionId, original.pairSessionId);
      expect(restored.controllerUrl, original.controllerUrl);
      expect(restored.deviceLabel, original.deviceLabel);
    });

    test('toString returns useful description', () {
      final data = QrPairingData(
        type: 'quoodle_pair',
        version: 1,
        deviceId: 'TEST-001',
        pairToken: 'token',
        pairSessionId: 'sess-123',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(data.toString(), contains('TEST-001'));
      expect(data.toString(), contains('sess-123'));
    });
  });

  group('QrParseException', () {
    test('toString includes message', () {
      const exception = QrParseException('test error');
      expect(exception.toString(), contains('test error'));
    });
  });
}
