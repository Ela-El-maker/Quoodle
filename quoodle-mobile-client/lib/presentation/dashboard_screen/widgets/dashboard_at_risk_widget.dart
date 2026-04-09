import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../routes/app_routes.dart';
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
            Text('At Risk', style: Theme.of(context).textTheme.titleMedium),
            TextButton(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.devicesScreen),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
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
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.deviceDetailScreen);
            },
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: _riskColor, width: 3),
            top: BorderSide(color: AppTheme.border, width: 1),
            right: BorderSide(color: AppTheme.border, width: 1),
            bottom: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadgeWidget.device(device.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device.reason,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${device.riskScore}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _riskColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'risk',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 9,
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
