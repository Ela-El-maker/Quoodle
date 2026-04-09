import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum DeviceStatus { online, offline, degraded, quarantined, pending }

enum CommandStatus {
  queued,
  dispatched,
  acked,
  executing,
  completed,
  failed,
  expired,
}

enum AlertSeverity { critical, high, warning, info }

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final Color color;
  final Color? backgroundColor;
  final double fontSize;
  final bool showDot;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
    this.fontSize = 11,
    this.showDot = false,
  });

  factory StatusBadgeWidget.device(DeviceStatus status) {
    final map = {
      DeviceStatus.online: ('ONLINE', AppTheme.statusOnline),
      DeviceStatus.offline: ('OFFLINE', AppTheme.statusOffline),
      DeviceStatus.degraded: ('DEGRADED', AppTheme.statusDegraded),
      DeviceStatus.quarantined: ('QUARANTINED', AppTheme.statusQuarantined),
      DeviceStatus.pending: ('PAIRING', AppTheme.statusPending),
    };
    final entry = map[status]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(38),
      showDot: true,
    );
  }

  factory StatusBadgeWidget.command(CommandStatus status) {
    final map = {
      CommandStatus.queued: ('QUEUED', AppTheme.primary),
      CommandStatus.dispatched: ('DISPATCHED', AppTheme.primary),
      CommandStatus.acked: ('ACKED', AppTheme.secondary),
      CommandStatus.executing: ('EXECUTING', AppTheme.warning),
      CommandStatus.completed: ('COMPLETED', AppTheme.statusOnline),
      CommandStatus.failed: ('FAILED', AppTheme.error),
      CommandStatus.expired: ('EXPIRED', AppTheme.statusOffline),
    };
    final entry = map[status]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(38),
    );
  }

  factory StatusBadgeWidget.alert(AlertSeverity severity) {
    final map = {
      AlertSeverity.critical: ('CRITICAL', AppTheme.critical),
      AlertSeverity.high: ('HIGH', AppTheme.error),
      AlertSeverity.warning: ('WARNING', AppTheme.warning),
      AlertSeverity.info: ('INFO', AppTheme.primary),
    };
    final entry = map[severity]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(38),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? color.withAlpha(38);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(102), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
