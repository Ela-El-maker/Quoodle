class AlertItem {
  const AlertItem({
    required this.alertId,
    required this.deviceId,
    required this.severity,
    required this.category,
    required this.message,
    required this.timestamp,
    required this.acknowledged,
  });

  final String? alertId;
  final String? deviceId;
  final String? severity;
  final String? category;
  final String? message;
  final String? timestamp;
  final bool acknowledged;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      alertId: json['alert_id'] as String?,
      deviceId: json['device_id'] as String?,
      severity: json['severity'] as String?,
      category: json['category'] as String?,
      message: json['message'] as String?,
      timestamp: json['timestamp'] as String?,
      acknowledged: json['acknowledged'] as bool? ?? false,
    );
  }
}
