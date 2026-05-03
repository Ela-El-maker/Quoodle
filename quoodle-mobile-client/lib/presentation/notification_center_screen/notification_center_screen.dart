import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/notifications/domain/entities/notification_item.dart';
import 'package:secure_device_control/features/notifications/presentation/providers/notification_providers.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  int _currentNavIndex = 3;

  void _onNavTap(int index) {
    if (index != _currentNavIndex) {
      setState(() => _currentNavIndex = index);
      AppNavigator.navigateToTab(
        context,
        index,
        profileTabTarget: ProfileTabTarget.settings,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationCenterControllerProvider);
    final controller = ref.read(notificationCenterControllerProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(state.unreadCount),
        body: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 56),
            _buildFilterRow(state),
            Expanded(
              child: state.filteredNotifications.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.notifications_none_rounded,
                      title: 'No Notifications',
                      subtitle: 'Notifications will appear here',
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      backgroundColor: AppTheme.surfaceVariant,
                      onRefresh: () async =>
                          await Future.delayed(Duration(milliseconds: 500)),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: state.filteredNotifications.length,
                        itemBuilder: (ctx, i) => _NotificationTile(
                          notification: state.filteredNotifications[i],
                          onTap: () => controller.openNotification(
                              state.filteredNotifications[i].id),
                          onDismiss: () => controller.deleteNotification(
                              state.filteredNotifications[i].id),
                          onMarkRead: () => controller
                              .markAsRead(state.filteredNotifications[i].id),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: AppNavigation(
          currentIndex: _currentNavIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }

  void _handleBack() {
    AppNavigator.popOrGo(context, AppRoute.alerts);
  }

  PreferredSizeWidget _buildAppBar(int unread) {
    final controller = ref.read(notificationCenterControllerProvider.notifier);
    return GlassAppBar(
      title: 'Notifications',
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: controller.markAllAsRead,
            child: Text(
              'Mark all read',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        IconButton(
          icon: Icon(Icons.delete_sweep_rounded, size: 20),
          onPressed: _confirmClearAll,
          tooltip: 'Clear all',
        ),
      ],
    );
  }

  Widget _buildFilterRow(NotificationCenterState state) {
    final controller = ref.read(notificationCenterControllerProvider.notifier);
    final unread = state.unreadCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // Unread toggle
          _FilterChip(
            label: 'Unread${unread > 0 ? ' ($unread)' : ''}',
            isSelected: state.showUnreadOnly,
            color: AppTheme.primary,
            onTap: controller.toggleUnreadOnly,
          ),
          SizedBox(width: 6),
          // Severity filters
          _FilterChip(
            label: 'Critical',
            isSelected:
                state.severityFilter == NotificationSeverityLevel.critical,
            color: AppTheme.critical,
            onTap: () => controller
                .toggleSeverityFilter(NotificationSeverityLevel.critical),
          ),
          SizedBox(width: 6),
          _FilterChip(
            label: 'High',
            isSelected: state.severityFilter == NotificationSeverityLevel.high,
            color: AppTheme.error,
            onTap: () =>
                controller.toggleSeverityFilter(NotificationSeverityLevel.high),
          ),
          SizedBox(width: 6),
          _FilterChip(
            label: 'Warning',
            isSelected:
                state.severityFilter == NotificationSeverityLevel.warning,
            color: AppTheme.warning,
            onTap: () => controller
                .toggleSeverityFilter(NotificationSeverityLevel.warning),
          ),
          SizedBox(width: 6),
          _FilterChip(
            label: 'Info',
            isSelected: state.severityFilter == NotificationSeverityLevel.info,
            color: AppTheme.secondary,
            onTap: () =>
                controller.toggleSeverityFilter(NotificationSeverityLevel.info),
          ),
          SizedBox(width: 10),
          // Category filters
          _FilterChip(
            label: 'Commands',
            isSelected:
                state.categoryFilter == NotificationCategoryType.command,
            color: AppTheme.primary,
            icon: Icons.terminal_rounded,
            onTap: () => controller
                .toggleCategoryFilter(NotificationCategoryType.command),
          ),
          SizedBox(width: 6),
          _FilterChip(
            label: 'Devices',
            isSelected: state.categoryFilter == NotificationCategoryType.device,
            color: AppTheme.primary,
            icon: Icons.devices_rounded,
            onTap: () => controller
                .toggleCategoryFilter(NotificationCategoryType.device),
          ),
          SizedBox(width: 6),
          _FilterChip(
            label: 'Alerts',
            isSelected: state.categoryFilter == NotificationCategoryType.alert,
            color: AppTheme.primary,
            icon: Icons.warning_amber_rounded,
            onTap: () =>
                controller.toggleCategoryFilter(NotificationCategoryType.alert),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    final controller = ref.read(notificationCenterControllerProvider.notifier);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All Notifications',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'This will permanently delete all notifications.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.clearAll();
            },
            child: Text(
              'Clear All',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(40) : AppTheme.glassLight,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: isSelected ? color.withAlpha(120) : AppTheme.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 11,
                color: isSelected ? color : AppTheme.textMuted,
              ),
              SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: isSelected ? color : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification Tile ─────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final VoidCallback onMarkRead;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
    required this.onMarkRead,
  });

  Color get _severityColor {
    switch (notification.severity) {
      case NotificationSeverityLevel.critical:
        return AppTheme.critical;
      case NotificationSeverityLevel.high:
        return AppTheme.error;
      case NotificationSeverityLevel.warning:
        return AppTheme.warning;
      case NotificationSeverityLevel.info:
        return AppTheme.primary;
    }
  }

  IconData get _categoryIcon {
    switch (notification.category) {
      case NotificationCategoryType.command:
        return Icons.terminal_rounded;
      case NotificationCategoryType.device:
        return Icons.devices_rounded;
      case NotificationCategoryType.alert:
        return Icons.warning_amber_rounded;
      case NotificationCategoryType.system:
        return Icons.settings_rounded;
    }
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(notification.timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.errorMuted,
          borderRadius: BorderRadius.circular(14.0),
        ),
        child: Icon(
          Icons.delete_rounded,
          color: AppTheme.error,
          size: 20,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: notification.isRead
                ? AppTheme.surfaceVariant
                : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(14.0),
            border: Border.all(
              color: notification.isRead
                  ? AppTheme.border
                  : _severityColor.withAlpha(80),
              width: notification.isRead ? 1 : 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Severity indicator bar
              Container(
                width: 4,
                height: 72,
                decoration: BoxDecoration(
                  color: notification.isRead ? AppTheme.border : _severityColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              SizedBox(width: 12),
              // Icon
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _severityColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Icon(_categoryIcon, size: 16, color: _severityColor),
                ),
              ),
              SizedBox(width: 10),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 13,
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          if (!notification.isRead)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _severityColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 3),
                      Text(
                        notification.body,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _timeAgo,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Spacer(),
                          if (notification.deepLinkRoute != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 11,
                                  color: AppTheme.primary,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
