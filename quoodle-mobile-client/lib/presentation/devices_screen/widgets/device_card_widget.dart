import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class DeviceCardWidget extends StatelessWidget {
  final Map<String, dynamic> device;
  final VoidCallback onTap;

  const DeviceCardWidget({
    super.key,
    required this.device,
    required this.onTap,
  });

  DeviceStatus get _status {
    switch (device['status'] as String) {
      case 'online':
        return DeviceStatus.online;
      case 'offline':
        return DeviceStatus.offline;
      case 'degraded':
        return DeviceStatus.degraded;
      case 'quarantined':
        return DeviceStatus.quarantined;
      default:
        return DeviceStatus.pending;
    }
  }

  Color get _riskColor {
    final score = device['riskScore'] as int;
    if (score >= 80) return AppTheme.critical;
    if (score >= 60) return AppTheme.error;
    if (score >= 40) return AppTheme.warning;
    return AppTheme.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: Icon(
                    _getOsIcon(device['os'] as String),
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device['name'] as String,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        device['id'] as String,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadgeWidget.device(_status),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                _MetricChip(
                  label: 'Risk',
                  value: '${device['riskScore']}',
                  color: _riskColor,
                ),
                SizedBox(width: 8),
                _MetricChip(
                  label: 'Compliance',
                  value: _complianceLabel(device['compliance'] as String),
                  color: _complianceColor(device['compliance'] as String),
                ),
                SizedBox(width: 8),
                _MetricChip(
                  label: 'Policy',
                  value: (device['policySync'] as bool) ? 'Synced' : 'Drift',
                  color: (device['policySync'] as bool)
                      ? AppTheme.secondary
                      : AppTheme.warning,
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 12,
                  color: AppTheme.textMuted,
                ),
                SizedBox(width: 4),
                Text(
                  'Seen ${device['lastSeen']}',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    device['os'] as String,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'v${device['agentVersion']}',
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

  IconData _getOsIcon(String os) {
    if (os.toLowerCase().contains('windows')) return Icons.window_rounded;
    if (os.toLowerCase().contains('ubuntu') ||
        os.toLowerCase().contains('debian')) {
      return Icons.terminal_rounded;
    }
    if (os.toLowerCase().contains('macos')) return Icons.laptop_mac_rounded;
    return Icons.devices_rounded;
  }

  String _complianceLabel(String c) {
    switch (c) {
      case 'compliant':
        return 'OK';
      case 'non_compliant':
        return 'Fail';
      default:
        return '?';
    }
  }

  Color _complianceColor(String c) {
    switch (c) {
      case 'compliant':
        return AppTheme.secondary;
      case 'non_compliant':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }
}

class _MetricChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: color.withAlpha(60), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
