import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class DashboardActivityFeedWidget extends StatelessWidget {
  const DashboardActivityFeedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final activities = [
      _ActivityItem(
        commandMethod: 'lock_screen',
        commandLabel: 'Lock Screen',
        deviceName: 'WKS-HR-003',
        status: CommandStatus.completed,
        timestamp: '10:52 AM',
        initiator: 'M. Okafor',
      ),
      _ActivityItem(
        commandMethod: 'collect_telemetry',
        commandLabel: 'Collect Telemetry',
        deviceName: 'PROD-SRV-014',
        status: CommandStatus.failed,
        timestamp: '10:44 AM',
        initiator: 'System',
      ),
      _ActivityItem(
        commandMethod: 'policy_sync',
        commandLabel: 'Policy Sync',
        deviceName: 'WKS-FINANCE-07',
        status: CommandStatus.executing,
        timestamp: '10:41 AM',
        initiator: 'L. Nakamura',
      ),
      _ActivityItem(
        commandMethod: 'reboot',
        commandLabel: 'Reboot',
        deviceName: 'EDGE-NODE-021',
        status: CommandStatus.queued,
        timestamp: '10:38 AM',
        initiator: 'A. Patel',
      ),
      _ActivityItem(
        commandMethod: 'screenshot_capture',
        commandLabel: 'Screenshot',
        deviceName: 'WKS-DEVOPS-11',
        status: CommandStatus.completed,
        timestamp: '10:22 AM',
        initiator: 'K. Santos',
      ),
    ];

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
                minimumSize: const Size(0, 0),
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
        const SizedBox(height: 8),
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
                    const Divider(
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
  const _ActivityItem({
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
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
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
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadgeWidget.command(item.status),
                const SizedBox(height: 4),
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
