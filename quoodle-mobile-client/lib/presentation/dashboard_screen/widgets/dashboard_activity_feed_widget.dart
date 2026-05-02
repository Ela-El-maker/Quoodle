import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class DashboardActivityFeedWidget extends ConsumerWidget {
  const DashboardActivityFeedWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      dashboardControllerProvider.select((state) => state.summary),
    );
    final activities = (summary?.recentActivities ?? [])
        .map(
          (event) => _ActivityItem(
            commandMethod: event.commandMethod,
            commandLabel: event.commandLabel,
            deviceName: event.deviceName,
            status: _mapCommandStatus(event.status),
            timestamp: event.timestampLabel,
            initiator: event.initiator,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () =>
                  AppNavigator.push(context, AppRoute.commandTimeline),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View all',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            children: List.generate(activities.length, (i) {
              final item = activities[i];
              return Column(
                children: [
                  _ActivityRow(
                    item: item,
                    onTap: () =>
                        AppNavigator.push(context, AppRoute.commandTimeline),
                  ),
                  if (i < activities.length - 1)
                    Divider(
                      height: 1,
                      color: AppTheme.borderLight,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _ActivityItem {
  final String commandMethod, commandLabel, deviceName, timestamp, initiator;
  final CommandStatus status;
  _ActivityItem({
    required this.commandMethod,
    required this.commandLabel,
    required this.deviceName,
    required this.status,
    required this.timestamp,
    required this.initiator,
  });
}

class _ActivityRow extends StatelessWidget {
  final _ActivityItem item;
  final VoidCallback onTap;
  const _ActivityRow({required this.item, required this.onTap});

  IconData get _methodIcon {
    switch (item.commandMethod) {
      case 'lock_screen':
        return Icons.lock_rounded;
      case 'reboot':
        return Icons.restart_alt_rounded;
      case 'collect_telemetry':
        return Icons.analytics_rounded;
      case 'policy_sync':
        return Icons.sync_rounded;
      case 'screenshot_capture':
        return Icons.screenshot_rounded;
      default:
        return Icons.terminal_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: Icon(_methodIcon, size: 15, color: AppTheme.textSecondary),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.commandLabel,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${item.deviceName} · ${item.initiator}',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadgeWidget.command(item.status),
                SizedBox(height: 4),
                Text(
                  item.timestamp,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

CommandStatus _mapCommandStatus(String status) {
  return switch (status) {
    'queued' => CommandStatus.queued,
    'dispatched' => CommandStatus.dispatched,
    'sent' => CommandStatus.dispatched,
    'ack_received' => CommandStatus.acked,
    'acked' => CommandStatus.acked,
    'executing' => CommandStatus.executing,
    'completed' => CommandStatus.completed,
    'failed' => CommandStatus.failed,
    'expired' => CommandStatus.expired,
    _ => CommandStatus.queued,
  };
}
