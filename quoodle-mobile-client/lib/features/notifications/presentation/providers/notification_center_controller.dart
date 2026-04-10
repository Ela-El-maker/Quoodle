import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';
import 'package:secure_device_control/features/notifications/di/notification_dependencies.dart';
import 'package:secure_device_control/features/notifications/presentation/providers/notification_center_state.dart';

class NotificationCenterController extends Notifier<NotificationCenterState> {
  bool _showUnreadOnly = false;
  NotificationSeverityLevel? _severityFilter;
  NotificationCategoryType? _categoryFilter;

  @override
  NotificationCenterState build() {
    ref.watch(notificationServiceNotifierProvider);
    return _buildState();
  }

  void toggleUnreadOnly() {
    _showUnreadOnly = !_showUnreadOnly;
    state = _buildState();
  }

  void toggleSeverityFilter(NotificationSeverityLevel severity) {
    _severityFilter = _severityFilter == severity ? null : severity;
    state = _buildState();
  }

  void toggleCategoryFilter(NotificationCategoryType category) {
    _categoryFilter = _categoryFilter == category ? null : category;
    state = _buildState();
  }

  void markAsRead(String notificationId) {
    ref.read(markNotificationAsReadProvider).call(notificationId);
    state = _buildState();
  }

  void markAllAsRead() {
    ref.read(markAllNotificationsAsReadProvider).call();
    state = _buildState();
  }

  void deleteNotification(String notificationId) {
    ref.read(deleteNotificationProvider).call(notificationId);
    state = _buildState();
  }

  void clearAll() {
    ref.read(clearAllNotificationsProvider).call();
    state = _buildState();
  }

  void openNotification(String notificationId) {
    ref.read(openNotificationProvider).call(notificationId);
    state = _buildState();
  }

  NotificationCenterState _buildState() {
    final notifications = ref.read(getNotificationsProvider).call();
    final unreadCount = ref.read(getUnreadNotificationCountProvider).call();

    final filtered = notifications.where((notification) {
      final matchesUnread = !_showUnreadOnly || !notification.isRead;
      final matchesSeverity =
          _severityFilter == null || notification.severity == _severityFilter;
      final matchesCategory =
          _categoryFilter == null || notification.category == _categoryFilter;
      return matchesUnread && matchesSeverity && matchesCategory;
    }).toList();

    return NotificationCenterState(
      notifications: notifications,
      filteredNotifications: filtered,
      unreadCount: unreadCount,
      showUnreadOnly: _showUnreadOnly,
      severityFilter: _severityFilter,
      categoryFilter: _categoryFilter,
    );
  }
}

final notificationCenterControllerProvider =
    NotifierProvider<NotificationCenterController, NotificationCenterState>(
  NotificationCenterController.new,
);
