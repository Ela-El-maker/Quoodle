import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class OpenNotification {
  const OpenNotification(this._repository);

  final NotificationRepository _repository;

  void call(String notificationId) {
    _repository.openNotification(notificationId);
  }
}
