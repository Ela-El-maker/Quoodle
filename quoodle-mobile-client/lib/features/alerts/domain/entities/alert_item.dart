enum AlertSeverityType { critical, high, warning, info }

extension AlertSeverityTypeValue on AlertSeverityType {
  String get value {
    switch (this) {
      case AlertSeverityType.critical:
        return 'critical';
      case AlertSeverityType.high:
        return 'high';
      case AlertSeverityType.warning:
        return 'warning';
      case AlertSeverityType.info:
        return 'info';
    }
  }
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.severity,
    required this.deviceId,
    required this.deviceName,
    required this.message,
    required this.timestamp,
    required this.acknowledged,
    required this.category,
  });

  final String id;
  final AlertSeverityType severity;
  final String deviceId;
  final String deviceName;
  final String message;
  final String timestamp;
  final bool acknowledged;
  final String category;

  AlertItem copyWith({bool? acknowledged}) {
    return AlertItem(
      id: id,
      severity: severity,
      deviceId: deviceId,
      deviceName: deviceName,
      message: message,
      timestamp: timestamp,
      acknowledged: acknowledged ?? this.acknowledged,
      category: category,
    );
  }
}
