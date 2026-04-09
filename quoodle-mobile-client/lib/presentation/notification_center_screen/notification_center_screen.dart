import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../services/push_notification_service.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final PushNotificationService _notifService = PushNotificationService();
  int _currentNavIndex = 3;
  NotificationSeverity? _severityFilter;
  NotificationCategory? _categoryFilter;
  bool _showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    _notifService.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _notifService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onNavTap(int index) {
    final routes = [
      AppRoutes.dashboardScreen,
      AppRoutes.devicesScreen,
      AppRoutes.commandTimelineScreen,
      AppRoutes.alertsScreen,
      AppRoutes.settingsScreen,
    ];
    if (index != _currentNavIndex) {
      setState(() => _currentNavIndex = index);
      Navigator.pushNamedAndRemoveUntil(
        context,
        routes[index],
        (route) => false,
      );
    }
  }

  List<AppNotification> get _filteredNotifications {
    var list = _notifService.notifications.toList();
    if (_showUnreadOnly) list = list.where((n) => !n.isRead).toList();
    if (_severityFilter != null) {
      list = list.where((n) => n.severity == _severityFilter).toList();
    }
    if (_categoryFilter != null) {
      list = list.where((n) => n.category == _categoryFilter).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifService.unreadCount;
    final filtered = _filteredNotifications;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(unread),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 56),
          _buildFilterRow(unread),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyStateWidget(
                    icon: Icons.notifications_none_rounded,
                    title: 'No Notifications',
                    subtitle: 'Notifications will appear here',
                  )
                : RefreshIndicator(
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surfaceVariant,
                    onRefresh: () async =>
                        await Future.delayed(const Duration(milliseconds: 500)),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _NotificationTile(
                        notification: filtered[i],
                        onTap: () =>
                            _notifService.navigateToDeepLink(filtered[i]),
                        onDismiss: () =>
                            _notifService.deleteNotification(filtered[i].id),
                        onMarkRead: () =>
                            _notifService.markAsRead(filtered[i].id),
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
    );
  }

  PreferredSizeWidget _buildAppBar(int unread) {
    return GlassAppBar(
      title: 'Notifications',
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: _notifService.markAllAsRead,
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
          icon: const Icon(Icons.delete_sweep_rounded, size: 20),
          onPressed: _confirmClearAll,
          tooltip: 'Clear all',
        ),
      ],
    );
  }

  Widget _buildFilterRow(int unread) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // Unread toggle
          _FilterChip(
            label: 'Unread${unread > 0 ? ' ($unread)' : ''}',
            isSelected: _showUnreadOnly,
            color: AppTheme.primary,
            onTap: () => setState(() => _showUnreadOnly = !_showUnreadOnly),
          ),
          const SizedBox(width: 6),
          // Severity filters
          _FilterChip(
            label: 'Critical',
            isSelected: _severityFilter == NotificationSeverity.critical,
            color: AppTheme.critical,
            onTap: () => setState(
              () => _severityFilter =
                  _severityFilter == NotificationSeverity.critical
                  ? null
                  : NotificationSeverity.critical,
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'High',
            isSelected: _severityFilter == NotificationSeverity.high,
            color: AppTheme.error,
            onTap: () => setState(
              () =>
                  _severityFilter = _severityFilter == NotificationSeverity.high
                  ? null
                  : NotificationSeverity.high,
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Warning',
            isSelected: _severityFilter == NotificationSeverity.warning,
            color: AppTheme.warning,
            onTap: () => setState(
              () => _severityFilter =
                  _severityFilter == NotificationSeverity.warning
                  ? null
                  : NotificationSeverity.warning,
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Info',
            isSelected: _severityFilter == NotificationSeverity.info,
            color: AppTheme.secondary,
            onTap: () => setState(
              () =>
                  _severityFilter = _severityFilter == NotificationSeverity.info
                  ? null
                  : NotificationSeverity.info,
            ),
          ),
          const SizedBox(width: 10),
          // Category filters
          _FilterChip(
            label: 'Commands',
            isSelected: _categoryFilter == NotificationCategory.command,
            color: AppTheme.primary,
            icon: Icons.terminal_rounded,
            onTap: () => setState(
              () => _categoryFilter =
                  _categoryFilter == NotificationCategory.command
                  ? null
                  : NotificationCategory.command,
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Devices',
            isSelected: _categoryFilter == NotificationCategory.device,
            color: AppTheme.primary,
            icon: Icons.devices_rounded,
            onTap: () => setState(
              () => _categoryFilter =
                  _categoryFilter == NotificationCategory.device
                  ? null
                  : NotificationCategory.device,
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Alerts',
            isSelected: _categoryFilter == NotificationCategory.alert,
            color: AppTheme.primary,
            icon: Icons.warning_amber_rounded,
            onTap: () => setState(
              () => _categoryFilter =
                  _categoryFilter == NotificationCategory.alert
                  ? null
                  : NotificationCategory.alert,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
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
              _notifService.clearAll();
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
        duration: const Duration(milliseconds: 150),
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
              const SizedBox(width: 4),
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
  final AppNotification notification;
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
      case NotificationSeverity.critical:
        return AppTheme.critical;
      case NotificationSeverity.high:
        return AppTheme.error;
      case NotificationSeverity.warning:
        return AppTheme.warning;
      case NotificationSeverity.info:
        return AppTheme.primary;
    }
  }

  IconData get _categoryIcon {
    switch (notification.category) {
      case NotificationCategory.command:
        return Icons.terminal_rounded;
      case NotificationCategory.device:
        return Icons.devices_rounded;
      case NotificationCategory.alert:
        return Icons.warning_amber_rounded;
      case NotificationCategory.system:
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
        child: const Icon(
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
              const SizedBox(width: 12),
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
              const SizedBox(width: 10),
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
                          const SizedBox(width: 8),
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
                      const SizedBox(height: 3),
                      Text(
                        notification.body,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _timeAgo,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const Spacer(),
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
                                const SizedBox(width: 2),
                                const Icon(
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