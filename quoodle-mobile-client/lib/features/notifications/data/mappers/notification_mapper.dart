import 'package:secure_device_control/core/services/push_notification_service.dart';
import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';

extension NotificationMapper on AppNotification {
  NotificationItem toDomain() {
    return NotificationItem(
      id: id,
      title: title,
      body: body,
      severity: _mapSeverity(severity),
      category: _mapCategory(category),
      timestamp: timestamp,
      isRead: isRead,
      deepLinkRoute: deepLinkRoute,
      deepLinkArgs: deepLinkArgs,
    );
  }
}

NotificationSeverityLevel _mapSeverity(NotificationSeverity severity) {
  switch (severity) {
    case NotificationSeverity.info:
      return NotificationSeverityLevel.info;
    case NotificationSeverity.warning:
      return NotificationSeverityLevel.warning;
    case NotificationSeverity.high:
      return NotificationSeverityLevel.high;
    case NotificationSeverity.critical:
      return NotificationSeverityLevel.critical;
  }
}

NotificationCategoryType _mapCategory(NotificationCategory category) {
  switch (category) {
    case NotificationCategory.command:
      return NotificationCategoryType.command;
    case NotificationCategory.device:
      return NotificationCategoryType.device;
    case NotificationCategory.alert:
      return NotificationCategoryType.alert;
    case NotificationCategory.system:
      return NotificationCategoryType.system;
  }
}
