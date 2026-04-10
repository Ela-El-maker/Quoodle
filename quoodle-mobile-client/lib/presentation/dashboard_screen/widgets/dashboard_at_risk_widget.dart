import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class DashboardAtRiskWidget extends StatelessWidget {
  const DashboardAtRiskWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final atRisk = [
      _AtRiskDevice(
        id: 'dev-014',
        name: 'PROD-SRV-014',
        status: DeviceStatus.offline,
        reason: 'No heartbeat for 18 min',
        riskScore: 94,
      ),
      _AtRiskDevice(
        id: 'dev-007',
        name: 'WKS-FINANCE-07',
        status: DeviceStatus.degraded,
        reason: 'Policy drift detected',
        riskScore: 71,
      ),
      _AtRiskDevice(
        id: 'dev-021',
        name: 'EDGE-NODE-021',
        status: DeviceStatus.quarantined,
        reason: 'Attestation failed',
        riskScore: 98,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'At Risk',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => AppNavigator.push(context, AppRoute.devices),
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
        ...atRisk.map(
          (d) => _AtRiskCard(
            device: d,
            onTap: () => AppNavigator.push(context, AppRoute.deviceDetail),
          ),
        ),
      ],
    );
  }
}

class _AtRiskDevice {
  final String id, name, reason;
  final DeviceStatus status;
  final int riskScore;
  const _AtRiskDevice({
    required this.id,
    required this.name,
    required this.status,
    required this.reason,
    required this.riskScore,
  });
}

class _AtRiskCard extends StatelessWidget {
  final _AtRiskDevice device;
  final VoidCallback onTap;
  const _AtRiskCard({required this.device, required this.onTap});

  Color get _riskColor {
    if (device.riskScore >= 90) return AppTheme.critical;
    if (device.riskScore >= 70) return AppTheme.error;
    return AppTheme.warning;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadgeWidget.device(device.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device.reason,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${device.riskScore}',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: _riskColor,
                  ),
                ),
                Text(
                  'risk',
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
