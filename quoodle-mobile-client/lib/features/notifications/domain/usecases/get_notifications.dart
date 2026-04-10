import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';
import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';

class GetNotifications {
  const GetNotifications(this._repository);

  final NotificationRepository _repository;

  List<NotificationItem> call() {
    return _repository.getNotifications();
  }
}
