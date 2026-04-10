import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class GetUnreadNotificationCount {
  const GetUnreadNotificationCount(this._repository);

  final NotificationRepository _repository;

  int call() {
    return _repository.getUnreadCount();
  }
}
