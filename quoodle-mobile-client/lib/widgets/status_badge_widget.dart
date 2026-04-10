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
    this.fontSize = 12,
    this.showDot = false,
  });

  factory StatusBadgeWidget.device(DeviceStatus status) {
    final map = {
      DeviceStatus.online: ('Online', AppTheme.statusOnline),
      DeviceStatus.offline: ('Offline', AppTheme.statusOffline),
      DeviceStatus.degraded: ('Degraded', AppTheme.statusDegraded),
      DeviceStatus.quarantined: ('Quarantined', AppTheme.statusQuarantined),
      DeviceStatus.pending: ('Pairing', AppTheme.statusPending),
    };
    final entry = map[status]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(30),
      showDot: true,
    );
  }

  factory StatusBadgeWidget.command(CommandStatus status) {
    final map = {
      CommandStatus.queued: ('Queued', AppTheme.primary),
      CommandStatus.dispatched: ('Dispatched', AppTheme.primary),
      CommandStatus.acked: ('Acked', AppTheme.secondary),
      CommandStatus.executing: ('Executing', AppTheme.warning),
      CommandStatus.completed: ('Completed', AppTheme.statusOnline),
      CommandStatus.failed: ('Failed', AppTheme.error),
      CommandStatus.expired: ('Expired', AppTheme.statusOffline),
    };
    final entry = map[status]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(30),
    );
  }

  factory StatusBadgeWidget.alert(AlertSeverity severity) {
    final map = {
      AlertSeverity.critical: ('Critical', AppTheme.critical),
      AlertSeverity.high: ('High', AppTheme.error),
      AlertSeverity.warning: ('Warning', AppTheme.warning),
      AlertSeverity.info: ('Info', AppTheme.primary),
    };
    final entry = map[severity]!;
    return StatusBadgeWidget(
      label: entry.$1,
      color: entry.$2,
      backgroundColor: entry.$2.withAlpha(30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? color.withAlpha(30);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: color.withAlpha(80), width: 1),
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
            style: GoogleFonts.ibmPlexSans(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
