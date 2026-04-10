import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';

abstract class NotificationRepository {
  List<NotificationItem> getNotifications();

  int getUnreadCount();

  void markAsRead(String notificationId);

  void markAllAsRead();

  void deleteNotification(String notificationId);

  void clearAll();

  void openNotification(String notificationId);
}
