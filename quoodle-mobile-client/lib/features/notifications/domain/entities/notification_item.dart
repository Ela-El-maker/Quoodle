enum NotificationSeverityLevel { info, warning, high, critical }

enum NotificationCategoryType { command, device, alert, system }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.category,
    required this.timestamp,
    required this.isRead,
    this.deepLinkRoute,
    this.deepLinkArgs,
  });

  final String id;
  final String title;
  final String body;
  final NotificationSeverityLevel severity;
  final NotificationCategoryType category;
  final DateTime timestamp;
  final bool isRead;
  final String? deepLinkRoute;
  final Map<String, dynamic>? deepLinkArgs;

  NotificationItem copyWith({
    bool? isRead,
  }) {
    return NotificationItem(
      id: id,
      title: title,
      body: body,
      severity: severity,
      category: category,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      deepLinkRoute: deepLinkRoute,
      deepLinkArgs: deepLinkArgs,
    );
  }
}
