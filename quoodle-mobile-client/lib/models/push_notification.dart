/// Types of push notifications the app can receive.
enum PushNotificationType {
  alert('alert'),
  command('command'),
  update('update'),
  deviceStatus('device_status'),
  security('security'),
  unknown('unknown');

  const PushNotificationType(this.value);
  final String value;

  static PushNotificationType fromString(String? value) {
    if (value == null) return PushNotificationType.unknown;
    for (final type in PushNotificationType.values) {
      if (type.value == value) return type;
    }
    return PushNotificationType.unknown;
  }
}

/// Severity level of a push notification.
enum PushSeverity {
  info('info'),
  warning('warning'),
  high('high'),
  critical('critical');

  const PushSeverity(this.value);
  final String value;

  static PushSeverity fromString(String? value) {
    if (value == null) return PushSeverity.info;
    for (final severity in PushSeverity.values) {
      if (severity.value == value) return severity;
    }
    return PushSeverity.info;
  }
}

/// Parsed push notification payload.
class PushNotificationPayload {
  const PushNotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    required this.severity,
    this.deviceId,
    this.alertId,
    this.commandId,
    this.resourceId,
    this.data,
    this.timestamp,
  });

  final PushNotificationType type;
  final String title;
  final String body;
  final PushSeverity severity;
  final String? deviceId;
  final String? alertId;
  final String? commandId;
  final String? resourceId;
  final Map<String, dynamic>? data;
  final DateTime? timestamp;

  factory PushNotificationPayload.fromMap(Map<String, dynamic> map) {
    final data = map['data'] as Map<String, dynamic>? ?? map;

    return PushNotificationPayload(
      type: PushNotificationType.fromString(data['type'] as String?),
      title: map['notification']?['title'] as String? ??
          data['title'] as String? ??
          'Notification',
      body: map['notification']?['body'] as String? ??
          data['body'] as String? ??
          '',
      severity: PushSeverity.fromString(data['severity'] as String?),
      deviceId: data['device_id'] as String?,
      alertId: data['alert_id'] as String?,
      commandId: data['command_id'] as String?,
      resourceId: data['resource_id'] as String?,
      data: data,
      timestamp: _parseTimestamp(data['timestamp']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  /// Whether this is a high-priority notification requiring immediate attention.
  bool get isUrgent =>
      severity == PushSeverity.critical || severity == PushSeverity.high;

  /// Whether this is a security-related notification.
  bool get isSecurityRelated =>
      type == PushNotificationType.security ||
      type == PushNotificationType.alert;

  @override
  String toString() => 'PushNotificationPayload('
      'type: ${type.value}, '
      'title: $title, '
      'severity: ${severity.value}, '
      'deviceId: $deviceId)';
}
