import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/core/services/push_notification_service.dart';
import 'package:secure_device_control/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:secure_device_control/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/clear_all_notifications.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/delete_notification.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/get_notifications.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/get_unread_notification_count.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/mark_all_notifications_as_read.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/mark_notification_as_read.dart';
import 'package:secure_device_control/features/notifications/domain/usecases/open_notification.dart';

final notificationServiceNotifierProvider =
    ChangeNotifierProvider<PushNotificationService>((ref) {
  return ref.read(pushNotificationServiceProvider);
});

final notificationServiceProvider = Provider<PushNotificationService>((ref) {
  return ref.watch(notificationServiceNotifierProvider);
});

final notificationLocalDataSourceProvider =
    Provider<NotificationLocalDataSource>(
  (ref) {
    return NotificationLocalDataSource(ref.watch(notificationServiceProvider));
  },
);

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(
      ref.watch(notificationLocalDataSourceProvider));
});

final getNotificationsProvider = Provider<GetNotifications>((ref) {
  return GetNotifications(ref.watch(notificationRepositoryProvider));
});

final getUnreadNotificationCountProvider =
    Provider<GetUnreadNotificationCount>((ref) {
  return GetUnreadNotificationCount(ref.watch(notificationRepositoryProvider));
});

final markNotificationAsReadProvider = Provider<MarkNotificationAsRead>((ref) {
  return MarkNotificationAsRead(ref.watch(notificationRepositoryProvider));
});

final markAllNotificationsAsReadProvider =
    Provider<MarkAllNotificationsAsRead>((ref) {
  return MarkAllNotificationsAsRead(ref.watch(notificationRepositoryProvider));
});

final deleteNotificationProvider = Provider<DeleteNotification>((ref) {
  return DeleteNotification(ref.watch(notificationRepositoryProvider));
});

final clearAllNotificationsProvider = Provider<ClearAllNotifications>((ref) {
  return ClearAllNotifications(ref.watch(notificationRepositoryProvider));
});

final openNotificationProvider = Provider<OpenNotification>((ref) {
  return OpenNotification(ref.watch(notificationRepositoryProvider));
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  ref.watch(notificationServiceNotifierProvider);
  return ref.watch(getUnreadNotificationCountProvider).call();
});
