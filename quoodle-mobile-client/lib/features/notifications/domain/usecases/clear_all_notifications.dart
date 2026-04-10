import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class ClearAllNotifications {
  const ClearAllNotifications(this._repository);

  final NotificationRepository _repository;

  void call() {
    _repository.clearAll();
  }
}
