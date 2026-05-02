import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';

class DeviceAuditTabWidget extends StatelessWidget {
  final String deviceId;
  const DeviceAuditTabWidget({super.key, required this.deviceId});

  static final List<Map<String, dynamic>> _auditMaps = [
    {
      'seq': 1094,
      'action': 'command.submitted',
      'actor': 'L. Nakamura',
      'role': 'operator',
      'detail': 'policy_sync dispatched to agent',
      'timestamp': '2026-04-06 10:41:03 UTC',
      'result': 'success',
    },
    {
      'seq': 1090,
      'action': 'alert.acknowledged',
      'actor': 'M. Okafor',
      'role': 'operator',
      'detail': 'Alert alert-024 acknowledged',
      'timestamp': '2026-04-06 09:58:12 UTC',
      'result': 'success',
    },
    {
      'seq': 1088,
      'action': 'command.failed',
      'actor': 'M. Okafor',
      'role': 'operator',
      'detail': 'lock_screen failed — agent unreachable',
      'timestamp': '2026-04-06 09:55:44 UTC',
      'result': 'failure',
    },
    {
      'seq': 1081,
      'action': 'policy.evaluated',
      'actor': 'System',
      'role': 'system',
      'detail': 'Policy evaluation: drift detected',
      'timestamp': '2026-04-06 09:38:00 UTC',
      'result': 'warning',
    },
    {
      'seq': 1072,
      'action': 'command.submitted',
      'actor': 'A. Patel',
      'role': 'operator',
      'detail': 'screenshot_capture completed successfully',
      'timestamp': '2026-04-06 09:30:17 UTC',
      'result': 'success',
    },
    {
      'seq': 1060,
      'action': 'device.connected',
      'actor': 'System',
      'role': 'system',
      'detail': 'Agent reconnected after 4m offline period',
      'timestamp': '2026-04-06 09:00:02 UTC',
      'result': 'success',
    },
  ];

  @override
  Widget build(BuildContext context) {
    if (_auditMaps.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'No audit records',
        subtitle: 'All device activity will be logged here for compliance.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: _auditMaps.length,
      itemBuilder: (ctx, i) => _AuditRow(entry: _auditMaps[i]),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _AuditRow({required this.entry});

  Color get _resultColor {
    switch (entry['result'] as String) {
      case 'success':
        return AppTheme.secondary;
      case 'failure':
        return AppTheme.error;
      case 'warning':
        return AppTheme.warning;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData get _actionIcon {
    final action = entry['action'] as String;
    if (action.startsWith('command')) return Icons.terminal_rounded;
    if (action.startsWith('alert')) return Icons.notifications_rounded;
    if (action.startsWith('policy')) return Icons.policy_rounded;
    if (action.startsWith('device')) return Icons.devices_rounded;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _resultColor.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_actionIcon, size: 14, color: _resultColor),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry['action'] as String,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Spacer(),
                    Text(
                      '#${entry['seq']}',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  entry['detail'] as String,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${entry['actor']} · ${entry['role']}',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    Spacer(),
                    Text(
                      entry['timestamp'] as String,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
