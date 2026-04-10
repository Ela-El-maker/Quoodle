import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class DeleteNotification {
  const DeleteNotification(this._repository);

  final NotificationRepository _repository;

  void call(String notificationId) {
    _repository.deleteNotification(notificationId);
  }
}
