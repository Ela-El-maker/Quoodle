import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/status_badge_widget.dart';

class DashboardActivityFeedWidget extends StatelessWidget {
  const DashboardActivityFeedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final activities = [
      _ActivityItem(
        commandMethod: 'lock_screen',
        deviceName: 'WKS-HR-003',
        status: CommandStatus.completed,
        timestamp: '10:52 AM',
        initiator: 'M. Okafor',
      ),
      _ActivityItem(
        commandMethod: 'collect_telemetry',
        deviceName: 'PROD-SRV-014',
        status: CommandStatus.failed,
        timestamp: '10:44 AM',
        initiator: 'System',
      ),
      _ActivityItem(
        commandMethod: 'policy_sync',
        deviceName: 'WKS-FINANCE-07',
        status: CommandStatus.executing,
        timestamp: '10:41 AM',
        initiator: 'L. Nakamura',
      ),
      _ActivityItem(
        commandMethod: 'reboot',
        deviceName: 'EDGE-NODE-021',
        status: CommandStatus.queued,
        timestamp: '10:38 AM',
        initiator: 'A. Patel',
      ),
      _ActivityItem(
        commandMethod: 'screenshot_capture',
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
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.commandTimelineScreen),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
              ),
              child: Text(
                'All commands',
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
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            children: List.generate(activities.length, (i) {
              final item = activities[i];
              return Column(
                children: [
                  _ActivityRow(
                    item: item,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.commandTimelineScreen,
                      );
                    },
                  ),
                  if (i < activities.length - 1)
                    const Divider(
                      height: 1,
                      color: AppTheme.borderLight,
                      indent: 52,
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
  final String commandMethod, deviceName, timestamp, initiator;
  final CommandStatus status;
  const _ActivityItem({
    required this.commandMethod,
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
      borderRadius: BorderRadius.circular(16),
      splashColor: AppTheme.primaryDim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: Icon(_methodIcon, size: 16, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.commandMethod,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.deviceName} · ${item.initiator}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadgeWidget.command(item.status),
                const SizedBox(height: 4),
                Text(
                  item.timestamp,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
