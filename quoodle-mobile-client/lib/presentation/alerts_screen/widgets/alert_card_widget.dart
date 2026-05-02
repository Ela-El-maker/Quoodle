import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class AlertCardWidget extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback? onAcknowledge;
  final VoidCallback onViewDevice;

  const AlertCardWidget({
    super.key,
    required this.alert,
    required this.onAcknowledge,
    required this.onViewDevice,
  });

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

  IconData get _categoryIcon {
    switch (alert['category'] as String) {
      case 'security':
        return Icons.security_rounded;
      case 'availability':
        return Icons.wifi_off_rounded;
      case 'compliance':
        return Icons.policy_rounded;
      case 'maintenance':
        return Icons.build_rounded;
      case 'performance':
        return Icons.speed_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAcked = alert['acknowledged'] as bool;

    return Dismissible(
      key: Key(alert['id'] as String),
      direction: isAcked ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withAlpha(38),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppTheme.secondary,
              size: 24,
            ),
            SizedBox(height: 4),
            Text(
              'Acknowledge',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 10,
                color: AppTheme.secondary,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onAcknowledge?.call(),
      confirmDismiss: (_) async {
        if (onAcknowledge == null) return false;
        onAcknowledge!();
        return false; // Don't actually remove from list — just ack
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isAcked ? AppTheme.background : AppTheme.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isAcked
                          ? AppTheme.surfaceVariant
                          : _severityColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Icon(
                      _categoryIcon,
                      size: 15,
                      color: isAcked ? AppTheme.textMuted : _severityColor,
                    ),
                  ),
                  SizedBox(width: 10),
                  StatusBadgeWidget.alert(_severity),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert['deviceName'] as String,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            isAcked ? AppTheme.textMuted : AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    alert['timestamp'] as String,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              // Message
              Text(
                alert['message'] as String,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: isAcked ? AppTheme.textMuted : AppTheme.textSecondary,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 12),
              // Action row
              Row(
                children: [
                  if (isAcked)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppTheme.statusOnline,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Acknowledged',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppTheme.statusOnline,
                          ),
                        ),
                      ],
                    )
                  else
                    InkWell(
                      onTap: onAcknowledge,
                      borderRadius: BorderRadius.circular(6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDim,
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(
                            color: AppTheme.primary.withAlpha(60),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Acknowledge',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  Spacer(),
                  InkWell(
                    onTap: onViewDevice,
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: AppTheme.border, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.devices_rounded,
                            size: 11,
                            color: AppTheme.textMuted,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'View Device',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
