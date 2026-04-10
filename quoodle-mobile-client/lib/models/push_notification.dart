enum PushNotificationType {
  alert('alert'),
  command('command'),
  update('update'),
  deviceStatus('device_status'),
  security('security'),
  unknown('unknown');

  const PushNotificationType(this.value);

  final String value;

  static PushNotificationType fromString(String? raw) {
    switch (raw) {
      case 'alert':
        return PushNotificationType.alert;
      case 'command':
        return PushNotificationType.command;
      case 'update':
        return PushNotificationType.update;
      case 'device_status':
        return PushNotificationType.deviceStatus;
      case 'security':
        return PushNotificationType.security;
      default:
        return PushNotificationType.unknown;
    }
  }
}

enum PushSeverity {
  info('info'),
  warning('warning'),
  high('high'),
  critical('critical');

  const PushSeverity(this.value);

  final String value;

  static PushSeverity fromString(String? raw) {
    switch (raw) {
      case 'warning':
        return PushSeverity.warning;
      case 'high':
        return PushSeverity.high;
      case 'critical':
        return PushSeverity.critical;
      case 'info':
      default:
        return PushSeverity.info;
    }
  }
}

class PushNotificationPayload {
  PushNotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    required this.severity,
    this.deviceId,
    this.alertId,
    this.commandId,
    this.timestamp,
    this.data,
  });

  final PushNotificationType type;
  final String title;
  final String body;
  final PushSeverity severity;
  final String? deviceId;
  final String? alertId;
  final String? commandId;
  final DateTime? timestamp;
  final Map<String, dynamic>? data;

  bool get isUrgent =>
      severity == PushSeverity.critical || severity == PushSeverity.high;

  bool get isSecurityRelated =>
      type == PushNotificationType.security ||
      type == PushNotificationType.alert;

  static PushNotificationPayload fromMap(Map<String, dynamic> map) {
    final notificationRaw = map['notification'];
    final notification = notificationRaw is Map
        ? notificationRaw.cast<String, dynamic>()
        : const <String, dynamic>{};

    final dataRaw = map['data'];
    final payloadData = dataRaw is Map ? dataRaw.cast<String, dynamic>() : map;

    final title =
        (notification['title'] ?? payloadData['title'] ?? 'Notification')
            .toString();
    final body = (notification['body'] ?? payloadData['body'] ?? '').toString();

    final timestamp = _parseTimestamp(payloadData['timestamp']);

    return PushNotificationPayload(
      type: PushNotificationType.fromString(payloadData['type']?.toString()),
      title: title,
      body: body,
      severity: PushSeverity.fromString(payloadData['severity']?.toString()),
      deviceId: payloadData['device_id']?.toString(),
      alertId: payloadData['alert_id']?.toString(),
      commandId: payloadData['command_id']?.toString(),
      timestamp: timestamp,
      data: payloadData,
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }

    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }

    return null;
  }

  @override
  String toString() {
    return 'PushNotificationPayload(type: ${type.value}, title: $title, severity: ${severity.value}, deviceId: $deviceId)';
  }
}
