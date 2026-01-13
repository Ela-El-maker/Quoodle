import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/models/push_notification.dart';

void main() {
  group('PushNotificationType', () {
    test('fromString returns correct enum for known types', () {
      expect(
          PushNotificationType.fromString('alert'), PushNotificationType.alert);
      expect(PushNotificationType.fromString('command'),
          PushNotificationType.command);
      expect(PushNotificationType.fromString('update'),
          PushNotificationType.update);
      expect(PushNotificationType.fromString('device_status'),
          PushNotificationType.deviceStatus);
      expect(PushNotificationType.fromString('security'),
          PushNotificationType.security);
    });

    test('fromString returns unknown for unrecognized types', () {
      expect(PushNotificationType.fromString('invalid'),
          PushNotificationType.unknown);
      expect(PushNotificationType.fromString(''), PushNotificationType.unknown);
      expect(
          PushNotificationType.fromString(null), PushNotificationType.unknown);
    });

    test('value property returns correct string', () {
      expect(PushNotificationType.alert.value, 'alert');
      expect(PushNotificationType.security.value, 'security');
      expect(PushNotificationType.unknown.value, 'unknown');
    });
  });

  group('PushSeverity', () {
    test('fromString returns correct enum for known severities', () {
      expect(PushSeverity.fromString('info'), PushSeverity.info);
      expect(PushSeverity.fromString('warning'), PushSeverity.warning);
      expect(PushSeverity.fromString('high'), PushSeverity.high);
      expect(PushSeverity.fromString('critical'), PushSeverity.critical);
    });

    test('fromString returns info as default', () {
      expect(PushSeverity.fromString('invalid'), PushSeverity.info);
      expect(PushSeverity.fromString(null), PushSeverity.info);
    });

    test('value property returns correct string', () {
      expect(PushSeverity.info.value, 'info');
      expect(PushSeverity.critical.value, 'critical');
    });
  });

  group('PushNotificationPayload', () {
    test('fromMap parses complete notification payload', () {
      final map = {
        'notification': {
          'title': 'Security Alert',
          'body': 'Threat detected on device',
        },
        'data': {
          'type': 'alert',
          'severity': 'critical',
          'device_id': 'device-123',
          'alert_id': 'alert-456',
          'timestamp': '2024-01-01T00:00:00Z',
        },
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.type, PushNotificationType.alert);
      expect(payload.title, 'Security Alert');
      expect(payload.body, 'Threat detected on device');
      expect(payload.severity, PushSeverity.critical);
      expect(payload.deviceId, 'device-123');
      expect(payload.alertId, 'alert-456');
    });

    test('fromMap handles data-only payload', () {
      final map = {
        'type': 'command',
        'title': 'Command Update',
        'body': 'Command completed',
        'severity': 'info',
        'command_id': 'cmd-789',
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.type, PushNotificationType.command);
      expect(payload.title, 'Command Update');
      expect(payload.commandId, 'cmd-789');
      expect(payload.severity, PushSeverity.info);
    });

    test('fromMap handles missing optional fields', () {
      final map = <String, dynamic>{
        'data': {
          'type': 'update',
        },
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.type, PushNotificationType.update);
      expect(payload.title, 'Notification');
      expect(payload.body, '');
      expect(payload.deviceId, isNull);
      expect(payload.alertId, isNull);
    });

    test('fromMap parses timestamp from ISO string', () {
      final map = {
        'data': {
          'type': 'alert',
          'timestamp': '2024-06-15T10:30:00Z',
        },
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.timestamp, isNotNull);
      expect(payload.timestamp!.year, 2024);
      expect(payload.timestamp!.month, 6);
      expect(payload.timestamp!.day, 15);
    });

    test('fromMap parses timestamp from milliseconds', () {
      final map = {
        'data': {
          'type': 'alert',
          'timestamp': 1718444400000, // 2024-06-15T10:00:00Z
        },
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.timestamp, isNotNull);
    });

    test('isUrgent returns true for critical and high severity', () {
      final critical = PushNotificationPayload.fromMap({
        'data': {'type': 'alert', 'severity': 'critical'},
      });
      final high = PushNotificationPayload.fromMap({
        'data': {'type': 'alert', 'severity': 'high'},
      });
      final warning = PushNotificationPayload.fromMap({
        'data': {'type': 'alert', 'severity': 'warning'},
      });
      final info = PushNotificationPayload.fromMap({
        'data': {'type': 'alert', 'severity': 'info'},
      });

      expect(critical.isUrgent, isTrue);
      expect(high.isUrgent, isTrue);
      expect(warning.isUrgent, isFalse);
      expect(info.isUrgent, isFalse);
    });

    test('isSecurityRelated returns true for security and alert types', () {
      final security = PushNotificationPayload.fromMap({
        'data': {'type': 'security'},
      });
      final alert = PushNotificationPayload.fromMap({
        'data': {'type': 'alert'},
      });
      final command = PushNotificationPayload.fromMap({
        'data': {'type': 'command'},
      });
      final update = PushNotificationPayload.fromMap({
        'data': {'type': 'update'},
      });

      expect(security.isSecurityRelated, isTrue);
      expect(alert.isSecurityRelated, isTrue);
      expect(command.isSecurityRelated, isFalse);
      expect(update.isSecurityRelated, isFalse);
    });

    test('toString provides useful debug info', () {
      final payload = PushNotificationPayload.fromMap({
        'notification': {'title': 'Test', 'body': 'Test body'},
        'data': {
          'type': 'alert',
          'severity': 'high',
          'device_id': 'device-123',
        },
      });

      final str = payload.toString();

      expect(str, contains('alert'));
      expect(str, contains('Test'));
      expect(str, contains('high'));
      expect(str, contains('device-123'));
    });

    test('data field preserves original payload', () {
      final map = {
        'data': {
          'type': 'alert',
          'custom_field': 'custom_value',
          'nested': {'key': 'value'},
        },
      };

      final payload = PushNotificationPayload.fromMap(map);

      expect(payload.data, isNotNull);
      expect(payload.data!['custom_field'], 'custom_value');
      expect(payload.data!['nested'], {'key': 'value'});
    });
  });
}
