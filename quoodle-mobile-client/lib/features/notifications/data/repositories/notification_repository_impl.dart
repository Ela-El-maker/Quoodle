import 'package:secure_device_control/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:secure_device_control/features/notifications/data/mappers/notification_mapper.dart';
import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';
import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._localDataSource);

  final NotificationLocalDataSource _localDataSource;

  @override
  List<NotificationItem> getNotifications() {
    return _localDataSource.notifications.map((n) => n.toDomain()).toList();
  }

  @override
  int getUnreadCount() {
    return _localDataSource.unreadCount;
  }

  @override
  void markAsRead(String notificationId) {
    _localDataSource.markAsRead(notificationId);
  }

  @override
  void markAllAsRead() {
    _localDataSource.markAllAsRead();
  }

  @override
  void deleteNotification(String notificationId) {
    _localDataSource.deleteNotification(notificationId);
  }

  @override
  void clearAll() {
    _localDataSource.clearAll();
  }

  @override
  void openNotification(String notificationId) {
    _localDataSource.navigateToDeepLink(notificationId);
  }
}
