import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';

class NotificationCenterState {
  const NotificationCenterState({
    required this.notifications,
    required this.filteredNotifications,
    required this.unreadCount,
    required this.showUnreadOnly,
    required this.severityFilter,
    required this.categoryFilter,
  });

  factory NotificationCenterState.initial() {
    return const NotificationCenterState(
      notifications: <NotificationItem>[],
      filteredNotifications: <NotificationItem>[],
      unreadCount: 0,
      showUnreadOnly: false,
      severityFilter: null,
      categoryFilter: null,
    );
  }

  final List<NotificationItem> notifications;
  final List<NotificationItem> filteredNotifications;
  final int unreadCount;
  final bool showUnreadOnly;
  final NotificationSeverityLevel? severityFilter;
  final NotificationCategoryType? categoryFilter;

  NotificationCenterState copyWith({
    List<NotificationItem>? notifications,
    List<NotificationItem>? filteredNotifications,
    int? unreadCount,
    bool? showUnreadOnly,
    NotificationSeverityLevel? severityFilter,
    NotificationCategoryType? categoryFilter,
    bool clearSeverityFilter = false,
    bool clearCategoryFilter = false,
  }) {
    return NotificationCenterState(
      notifications: notifications ?? this.notifications,
      filteredNotifications:
          filteredNotifications ?? this.filteredNotifications,
      unreadCount: unreadCount ?? this.unreadCount,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      severityFilter:
          clearSeverityFilter ? null : (severityFilter ?? this.severityFilter),
      categoryFilter:
          clearCategoryFilter ? null : (categoryFilter ?? this.categoryFilter),
    );
  }
}
