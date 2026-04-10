import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';
import '../../../widgets/empty_state_widget.dart';

class DeviceCommandsTabWidget extends StatelessWidget {
  final String deviceId;
  const DeviceCommandsTabWidget({super.key, required this.deviceId});

  static final List<Map<String, dynamic>> _commandMaps = [
    {
      'id': 'cmd-0091',
      'method': 'policy_sync',
      'status': 'executing',
      'initiator': 'L. Nakamura',
      'queuedAt': '10:41 AM',
      'completedAt': null,
      'sensitive': false,
      'resultType': null,
    },
    {
      'id': 'cmd-0087',
      'method': 'collect_telemetry',
      'status': 'completed',
      'initiator': 'System',
      'queuedAt': '10:20 AM',
      'completedAt': '10:20 AM',
      'sensitive': false,
      'resultType': 'telemetry',
    },
    {
      'id': 'cmd-0085',
      'method': 'screenshot_capture',
      'status': 'completed',
      'initiator': 'A. Patel',
      'queuedAt': '10:05 AM',
      'completedAt': '10:05 AM',
      'sensitive': true,
      'resultType': 'screenshot',
    },
    {
      'id': 'cmd-0082',
      'method': 'lock_screen',
      'status': 'failed',
      'initiator': 'M. Okafor',
      'queuedAt': '09:55 AM',
      'completedAt': '09:55 AM',
      'sensitive': false,
      'resultType': null,
    },
    {
      'id': 'cmd-0080',
      'method': 'process_list',
      'status': 'completed',
      'initiator': 'System',
      'queuedAt': '09:40 AM',
      'completedAt': '09:40 AM',
      'sensitive': false,
      'resultType': 'process_list',
    },
    {
      'id': 'cmd-0079',
      'method': 'system_info',
      'status': 'completed',
      'initiator': 'A. Patel',
      'queuedAt': '09:30 AM',
      'completedAt': '09:31 AM',
      'sensitive': false,
      'resultType': 'system_info',
    },
    {
      'id': 'cmd-0076',
      'method': 'network_info',
      'status': 'completed',
      'initiator': 'System',
      'queuedAt': '09:15 AM',
      'completedAt': '09:15 AM',
      'sensitive': false,
      'resultType': 'network_info',
    },
    {
      'id': 'cmd-0073',
      'method': 'running_apps',
      'status': 'completed',
      'initiator': 'L. Nakamura',
      'queuedAt': '09:00 AM',
      'completedAt': '09:00 AM',
      'sensitive': false,
      'resultType': 'running_apps',
    },
    {
      'id': 'cmd-0071',
      'method': 'filesystem',
      'status': 'completed',
      'initiator': 'A. Patel',
      'queuedAt': '08:45 AM',
      'completedAt': '08:46 AM',
      'sensitive': true,
      'resultType': 'filesystem',
    },
    {
      'id': 'cmd-0068',
      'method': 'upload_file',
      'status': 'completed',
      'initiator': 'M. Okafor',
      'queuedAt': '08:30 AM',
      'completedAt': '08:31 AM',
      'sensitive': true,
      'resultType': 'file_op',
    },
    {
      'id': 'cmd-0065',
      'method': 'policy_sync',
      'status': 'completed',
      'initiator': 'System',
      'queuedAt': '08:00 AM',
      'completedAt': '08:01 AM',
      'sensitive': false,
      'resultType': null,
    },
  ];

  @override
  Widget build(BuildContext context) {
    if (_commandMaps.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.terminal_rounded,
        title: 'No commands yet',
        subtitle:
            'Commands sent to this device will appear here with their full execution history.',
      );
    }
    return Column(
      children: [
        // Summary bar
        _buildSummaryBar(context),
        // Command list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: _commandMaps.length,
            itemBuilder: (ctx, i) {
              final cmd = _commandMaps[i];
              return _CommandHistoryCard(
                command: cmd,
                onTap: () => AppNavigator.push(
                  ctx,
                  AppRoute.commandTimeline,
                  arguments: cmd,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(BuildContext context) {
    final total = _commandMaps.length;
    final completed =
        _commandMaps.where((c) => c['status'] == 'completed').length;
    final failed = _commandMaps.where((c) => c['status'] == 'failed').length;
    final executing =
        _commandMaps.where((c) => c['status'] == 'executing').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Row(
        children: [
          _SummaryChip(label: '$total Total', color: AppTheme.textMuted),
          const SizedBox(width: 8),
          _SummaryChip(label: '$completed OK', color: AppTheme.secondary),
          const SizedBox(width: 8),
          if (executing > 0) ...[
            _SummaryChip(label: '$executing Running', color: AppTheme.warning),
            const SizedBox(width: 8),
          ],
          if (failed > 0)
            _SummaryChip(label: '$failed Failed', color: AppTheme.error),
          const Spacer(),
          GestureDetector(
            onTap: () => AppNavigator.push(context, AppRoute.sendCommand),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(102)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'New',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CommandHistoryCard extends StatelessWidget {
  final Map<String, dynamic> command;
  final VoidCallback onTap;
  const _CommandHistoryCard({required this.command, required this.onTap});

  CommandStatus get _status {
    switch (command['status'] as String) {
      case 'queued':
        return CommandStatus.queued;
      case 'dispatched':
        return CommandStatus.dispatched;
      case 'acked':
        return CommandStatus.acked;
      case 'executing':
        return CommandStatus.executing;
      case 'completed':
        return CommandStatus.completed;
      case 'failed':
        return CommandStatus.failed;
      default:
        return CommandStatus.expired;
    }
  }

  IconData get _methodIcon {
    switch (command['method'] as String) {
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
      case 'process_list':
        return Icons.account_tree_rounded;
      case 'system_info':
        return Icons.info_outline_rounded;
      case 'running_apps':
        return Icons.apps_rounded;
      case 'filesystem':
        return Icons.folder_open_rounded;
      case 'network_info':
        return Icons.lan_rounded;
      case 'upload_file':
        return Icons.upload_rounded;
      case 'create_file':
        return Icons.note_add_rounded;
      default:
        return Icons.terminal_rounded;
    }
  }

  Color get _methodColor {
    switch (command['method'] as String) {
      case 'screenshot_capture':
      case 'filesystem':
      case 'upload_file':
      case 'create_file':
      case 'reboot':
        return AppTheme.warning;
      case 'lock_screen':
        return AppTheme.error;
      case 'collect_telemetry':
      case 'system_info':
      case 'running_apps':
      case 'network_info':
        return AppTheme.secondary;
      default:
        return AppTheme.primary;
    }
  }

  String get _resultTypeLabel {
    final rt = command['resultType'] as String?;
    switch (rt) {
      case 'screenshot':
        return 'Screenshot';
      case 'process_list':
        return 'Process Table';
      case 'system_info':
        return 'System Report';
      case 'running_apps':
        return 'App List';
      case 'filesystem':
        return 'File Tree';
      case 'network_info':
        return 'Network Map';
      case 'file_op':
        return 'File Op';
      case 'telemetry':
        return 'Metrics';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = (command['resultType'] as String?) != null &&
        command['status'] == 'completed';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      splashColor: AppTheme.primaryDim,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _methodColor.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _methodColor.withAlpha(64)),
              ),
              child: Icon(_methodIcon, size: 17, color: _methodColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          command['method'] as String,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (command['sensitive'] as bool) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.security_rounded,
                          size: 11,
                          color: AppTheme.warning,
                        ),
                      ],
                      if (hasResult) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryDim,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _resultTypeLabel,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 9,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        command['id'] as String,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '· ${command['initiator']}',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadgeWidget.command(_status),
                const SizedBox(height: 4),
                Text(
                  command['queuedAt'] as String,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
