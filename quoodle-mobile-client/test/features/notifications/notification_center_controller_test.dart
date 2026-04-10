import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';
import 'package:secure_device_control/features/notifications/domain/repositories/notification_repository.dart';
import 'package:secure_device_control/features/notifications/presentation/providers/notification_providers.dart';

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this._notifications);

  final List<NotificationItem> _notifications;

  @override
  List<NotificationItem> getNotifications() {
    return List<NotificationItem>.unmodifiable(_notifications);
  }

  @override
  int getUnreadCount() {
    return _notifications.where((n) => !n.isRead).length;
  }

  @override
  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;
    _notifications[index] = _notifications[index].copyWith(isRead: true);
  }

  @override
  void markAllAsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }

  @override
  void deleteNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
  }

  @override
  void clearAll() {
    _notifications.clear();
  }

  @override
  void openNotification(String notificationId) {
    markAsRead(notificationId);
  }
}

void main() {
  group('NotificationCenterController', () {
    test('applies filters and updates state after actions', () {
      final fakeRepository = _FakeNotificationRepository([
        NotificationItem(
          id: 'n1',
          title: 'Critical alert',
          body: 'edge node quarantined',
          severity: NotificationSeverityLevel.critical,
          category: NotificationCategoryType.alert,
          timestamp: DateTime(2026, 4, 10, 10),
          isRead: false,
          deepLinkRoute: '/alerts-screen',
        ),
        NotificationItem(
          id: 'n2',
          title: 'Device offline',
          body: 'prod-01 offline',
          severity: NotificationSeverityLevel.high,
          category: NotificationCategoryType.device,
          timestamp: DateTime(2026, 4, 10, 11),
          isRead: false,
          deepLinkRoute: '/device-detail-screen',
        ),
        NotificationItem(
          id: 'n3',
          title: 'Command completed',
          body: 'collect telemetry done',
          severity: NotificationSeverityLevel.info,
          category: NotificationCategoryType.command,
          timestamp: DateTime(2026, 4, 10, 12),
          isRead: true,
          deepLinkRoute: '/command-timeline-screen',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        notificationCenterControllerProvider.notifier,
      );

      expect(
        container.read(notificationCenterControllerProvider).unreadCount,
        2,
      );
      expect(
        container
            .read(notificationCenterControllerProvider)
            .filteredNotifications
            .length,
        3,
      );

      controller.toggleUnreadOnly();
      expect(
        container
            .read(notificationCenterControllerProvider)
            .filteredNotifications
            .length,
        2,
      );

      controller.toggleSeverityFilter(NotificationSeverityLevel.critical);
      expect(
        container
            .read(notificationCenterControllerProvider)
            .filteredNotifications
            .single
            .id,
        'n1',
      );

      controller.markAsRead('n1');
      expect(
        container.read(notificationCenterControllerProvider).unreadCount,
        1,
      );

      controller.deleteNotification('n2');
      expect(
        container
            .read(notificationCenterControllerProvider)
            .notifications
            .length,
        2,
      );
    });
  });
}
