import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';
import '../../../widgets/empty_state_widget.dart';

class DeviceAlertsTabWidget extends StatefulWidget {
  final String deviceId;
  const DeviceAlertsTabWidget({super.key, required this.deviceId});

  @override
  State<DeviceAlertsTabWidget> createState() => _DeviceAlertsTabWidgetState();
}

class _DeviceAlertsTabWidgetState extends State<DeviceAlertsTabWidget> {
  // TODO: Replace with Riverpod/Bloc for production
  final List<Map<String, dynamic>> _alertMaps = [
    {
      'id': 'alert-031',
      'severity': 'high',
      'message':
          'Policy drift detected — reported hash does not match expected',
      'timestamp': '10:38 AM',
      'acknowledged': false,
    },
    {
      'id': 'alert-028',
      'severity': 'warning',
      'message': 'Agent version 2.0.9 is below minimum recommended (2.1.x)',
      'timestamp': '09:12 AM',
      'acknowledged': false,
    },
    {
      'id': 'alert-024',
      'severity': 'info',
      'message': 'Scheduled compliance scan completed — 2 rules failed',
      'timestamp': '08:00 AM',
      'acknowledged': true,
    },
  ];

  void _acknowledge(int index) {
    setState(() {
      _alertMaps[index] = {..._alertMaps[index], 'acknowledged': true};
    });
  }

  @override
  Widget build(BuildContext context) {
    final unacked = _alertMaps
        .where((a) => !(a['acknowledged'] as bool))
        .length;
    if (_alertMaps.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.notifications_off_rounded,
        title: 'No alerts for this device',
        subtitle: 'This device is operating within normal parameters.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        if (unacked > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.errorMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.error,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Text(
                  '$unacked unacknowledged alert${unacked > 1 ? 's' : ''}',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
        ...List.generate(_alertMaps.length, (i) {
          final alert = _alertMaps[i];
          return _DeviceAlertCard(
            alert: alert,
            onAcknowledge: (alert['acknowledged'] as bool)
                ? null
                : () => _acknowledge(i),
          );
        }),
      ],
    );
  }
}

class _DeviceAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback? onAcknowledge;
  const _DeviceAlertCard({required this.alert, required this.onAcknowledge});

  AlertSeverity get _severity {
    switch (alert['severity'] as String) {
      case 'critical':
        return AlertSeverity.critical;
      case 'high':
        return AlertSeverity.high;
      case 'warning':
        return AlertSeverity.warning;
      default:
        return AlertSeverity.info;
    }
  }

  Color get _severityColor {
    switch (_severity) {
      case AlertSeverity.critical:
        return AppTheme.critical;
      case AlertSeverity.high:
        return AppTheme.error;
      case AlertSeverity.warning:
        return AppTheme.warning;
      case AlertSeverity.info:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAcked = alert['acknowledged'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAcked ? AppTheme.surface : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: isAcked ? AppTheme.border : _severityColor,
            width: isAcked ? 1 : 3,
          ),
          top: const BorderSide(color: AppTheme.border, width: 1),
          right: const BorderSide(color: AppTheme.border, width: 1),
          bottom: const BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadgeWidget.alert(_severity),
              const SizedBox(width: 8),
              Text(
                alert['timestamp'] as String,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(),
              if (isAcked)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 12,
                      color: AppTheme.statusOnline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Acked',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: AppTheme.statusOnline,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert['message'] as String,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: isAcked ? AppTheme.textMuted : AppTheme.textPrimary,
            ),
          ),
          if (!isAcked && onAcknowledge != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAcknowledge,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  backgroundColor: AppTheme.primaryDim,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Acknowledge',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
