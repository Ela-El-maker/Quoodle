import 'package:secure_device_control/core/services/push_notification_service.dart';

class NotificationLocalDataSource {
  const NotificationLocalDataSource(this._service);

  final PushNotificationService _service;

  List<AppNotification> get notifications => _service.notifications;

  int get unreadCount => _service.unreadCount;

  void markAsRead(String notificationId) {
    _service.markAsRead(notificationId);
  }

  void markAllAsRead() {
    _service.markAllAsRead();
  }

  void deleteNotification(String notificationId) {
    _service.deleteNotification(notificationId);
  }

  void clearAll() {
    _service.clearAll();
  }

  void navigateToDeepLink(String notificationId) {
    for (final notification in _service.notifications) {
      if (notification.id == notificationId) {
        _service.navigateToDeepLink(notification);
        return;
      }
    }
  }
}
