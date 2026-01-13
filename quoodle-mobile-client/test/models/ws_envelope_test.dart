import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/models/ws_envelope.dart';

void main() {
  group('WsMessageType', () {
    test('fromString returns correct enum for known types', () {
      expect(WsMessageType.fromString('AUTH'), WsMessageType.auth);
      expect(WsMessageType.fromString('AUTH_ACK'), WsMessageType.authAck);
      expect(WsMessageType.fromString('AUTH_ERROR'), WsMessageType.authError);
      expect(WsMessageType.fromString('HEARTBEAT'), WsMessageType.heartbeat);
      expect(WsMessageType.fromString('TELEMETRY'), WsMessageType.telemetry);
      expect(WsMessageType.fromString('COMMAND_DELIVERY'),
          WsMessageType.commandDelivery);
      expect(WsMessageType.fromString('COMMAND_ACK'), WsMessageType.commandAck);
      expect(WsMessageType.fromString('COMMAND_RESULT'),
          WsMessageType.commandResult);
      expect(WsMessageType.fromString('ALERT'), WsMessageType.alert);
      expect(WsMessageType.fromString('UPDATE'), WsMessageType.update);
    });

    test('fromString returns unknown for unrecognized types', () {
      expect(WsMessageType.fromString('INVALID'), WsMessageType.unknown);
      expect(WsMessageType.fromString(''), WsMessageType.unknown);
      expect(WsMessageType.fromString(null), WsMessageType.unknown);
    });

    test('value property returns correct string', () {
      expect(WsMessageType.auth.value, 'AUTH');
      expect(WsMessageType.authAck.value, 'AUTH_ACK');
      expect(WsMessageType.unknown.value, 'UNKNOWN');
    });
  });

  group('WsEnvelope', () {
    test('fromJson parses valid envelope', () {
      final json = {
        'message_id': 'msg-123',
        'timestamp': '2024-01-01T00:00:00Z',
        'type': 'AUTH_ACK',
        'from': 'controller',
        'device_id': 'device-456',
        'session_id': 'session-789',
        'body': {'status': 'ok'},
        'sig': 'signature-abc',
      };

      final envelope = WsEnvelope.fromJson(json);

      expect(envelope.messageId, 'msg-123');
      expect(envelope.timestamp, '2024-01-01T00:00:00Z');
      expect(envelope.type, WsMessageType.authAck);
      expect(envelope.from, 'controller');
      expect(envelope.deviceId, 'device-456');
      expect(envelope.sessionId, 'session-789');
      expect(envelope.body, {'status': 'ok'});
      expect(envelope.sig, 'signature-abc');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'message_id': 'msg-123',
        'timestamp': '2024-01-01T00:00:00Z',
        'type': 'HEARTBEAT',
        'from': 'agent',
        'device_id': 'device-456',
        'body': {'status': 'healthy'},
        'sig': 'sig-xyz',
      };

      final envelope = WsEnvelope.fromJson(json);

      expect(envelope.sessionId, isNull);
      expect(envelope.isValid, isTrue);
    });

    test('fromJson handles missing required fields gracefully', () {
      final envelope = WsEnvelope.fromJson({});

      expect(envelope.messageId, '');
      expect(envelope.timestamp, '');
      expect(envelope.type, WsMessageType.unknown);
      expect(envelope.from, '');
      expect(envelope.deviceId, '');
      expect(envelope.body, <String, dynamic>{});
      expect(envelope.sig, '');
      expect(envelope.isValid, isFalse);
    });

    test('parse handles JSON string', () {
      const jsonStr = '{"message_id":"m1","timestamp":"2024-01-01T00:00:00Z",'
          '"type":"ALERT","from":"controller","device_id":"d1",'
          '"body":{},"sig":"s1"}';

      final envelope = WsEnvelope.parse(jsonStr);

      expect(envelope.messageId, 'm1');
      expect(envelope.type, WsMessageType.alert);
    });

    test('toJson produces correct output', () {
      const envelope = WsEnvelope(
        messageId: 'msg-1',
        timestamp: '2024-01-01T00:00:00Z',
        type: WsMessageType.heartbeat,
        from: 'mobile',
        deviceId: 'device-1',
        sessionId: 'session-1',
        body: {'status': 'healthy'},
        sig: 'sig-1',
      );

      final json = envelope.toJson();

      expect(json['message_id'], 'msg-1');
      expect(json['type'], 'HEARTBEAT');
      expect(json['from'], 'mobile');
      expect(json['session_id'], 'session-1');
    });

    test('isValid returns true for complete envelope', () {
      const envelope = WsEnvelope(
        messageId: 'msg-1',
        timestamp: '2024-01-01T00:00:00Z',
        type: WsMessageType.authAck,
        from: 'controller',
        deviceId: 'device-1',
        body: {},
        sig: 'sig-1',
      );

      expect(envelope.isValid, isTrue);
    });

    test('isValid returns false for incomplete envelope', () {
      const envelope = WsEnvelope(
        messageId: '',
        timestamp: '2024-01-01T00:00:00Z',
        type: WsMessageType.authAck,
        from: 'controller',
        deviceId: 'device-1',
        body: {},
        sig: 'sig-1',
      );

      expect(envelope.isValid, isFalse);
    });
  });

  group('AuthAckBody', () {
    test('fromJson parses valid auth ack', () {
      final json = {
        'status': 'ok',
        'session_id': 'session-123',
        'heartbeat_interval_seconds': 30,
        'telemetry_interval_seconds': 60,
        'policy_hash': 'hash-abc',
      };

      final ack = AuthAckBody.fromJson(json);

      expect(ack.status, 'ok');
      expect(ack.sessionId, 'session-123');
      expect(ack.heartbeatIntervalSeconds, 30);
      expect(ack.telemetryIntervalSeconds, 60);
      expect(ack.policyHash, 'hash-abc');
      expect(ack.isOk, isTrue);
    });

    test('fromJson uses defaults for missing fields', () {
      final ack = AuthAckBody.fromJson({});

      expect(ack.status, '');
      expect(ack.sessionId, '');
      expect(ack.heartbeatIntervalSeconds, 30);
      expect(ack.telemetryIntervalSeconds, 60);
      expect(ack.policyHash, isNull);
      expect(ack.isOk, isFalse);
    });
  });

  group('AuthErrorBody', () {
    test('fromJson parses valid auth error', () {
      final json = {
        'status': 'error',
        'error_code': 'AUTH_FAILED',
        'error_message': 'Invalid JWT',
      };

      final error = AuthErrorBody.fromJson(json);

      expect(error.status, 'error');
      expect(error.errorCode, 'AUTH_FAILED');
      expect(error.errorMessage, 'Invalid JWT');
    });

    test('fromJson provides defaults', () {
      final error = AuthErrorBody.fromJson({});

      expect(error.status, 'error');
      expect(error.errorCode, 'UNKNOWN');
      expect(error.errorMessage, '');
    });
  });

  group('CommandDeliveryBody', () {
    test('fromJson parses valid command delivery', () {
      final json = {
        'command_message_id': 'cmd-123',
        'method': 'quarantine_file',
        'params': {'path': '/tmp/virus.exe'},
        'priority': 'high',
        'ttl_seconds': 120,
        'requires_ack': true,
      };

      final cmd = CommandDeliveryBody.fromJson(json);

      expect(cmd.commandMessageId, 'cmd-123');
      expect(cmd.method, 'quarantine_file');
      expect(cmd.params, {'path': '/tmp/virus.exe'});
      expect(cmd.priority, 'high');
      expect(cmd.ttlSeconds, 120);
      expect(cmd.requiresAck, isTrue);
    });

    test('fromJson uses defaults', () {
      final cmd = CommandDeliveryBody.fromJson({});

      expect(cmd.commandMessageId, '');
      expect(cmd.method, '');
      expect(cmd.params, <String, dynamic>{});
      expect(cmd.priority, 'normal');
      expect(cmd.ttlSeconds, 300);
      expect(cmd.requiresAck, isTrue);
    });
  });

  group('AlertBody', () {
    test('fromJson parses valid alert', () {
      final json = {
        'alert_id': 'alert-123',
        'severity': 'critical',
        'category': 'malware',
        'message': 'Threat detected',
        'timestamp': '2024-01-01T00:00:00Z',
      };

      final alert = AlertBody.fromJson(json);

      expect(alert.alertId, 'alert-123');
      expect(alert.severity, 'critical');
      expect(alert.category, 'malware');
      expect(alert.message, 'Threat detected');
      expect(alert.timestamp, '2024-01-01T00:00:00Z');
    });

    test('fromJson provides defaults', () {
      final alert = AlertBody.fromJson({});

      expect(alert.alertId, '');
      expect(alert.severity, 'info');
      expect(alert.category, '');
      expect(alert.message, '');
      expect(alert.timestamp, '');
    });
  });

  group('UpdateBody', () {
    test('fromJson parses valid update', () {
      final json = {
        'update_type': 'device_status',
        'resource_id': 'device-123',
        'resource_type': 'device',
        'data': {'status': 'online'},
      };

      final update = UpdateBody.fromJson(json);

      expect(update.updateType, 'device_status');
      expect(update.resourceId, 'device-123');
      expect(update.resourceType, 'device');
      expect(update.data, {'status': 'online'});
    });

    test('fromJson handles missing data', () {
      final update = UpdateBody.fromJson({
        'update_type': 'refresh',
        'resource_id': 'r1',
        'resource_type': 'policy',
      });

      expect(update.updateType, 'refresh');
      expect(update.data, isNull);
    });
  });
}
