import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_colors.dart';
import 'compliance_badge.dart';
import 'glass_card.dart';
import 'risk_gauge.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
  });

  final Device device;
  final VoidCallback? onTap;

  bool get _online {
    final state = device.lifecycleState.toLowerCase();
    return state.contains('online') || state.contains('active');
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.complianceColor(device.complianceStatus);
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: 1,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _online ? AppColors.accentMint : AppColors.textMuted,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_online
                                ? AppColors.accentMint
                                : AppColors.textMuted)
                            .withOpacity(0.5),
                        blurRadius: 8,
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.deviceName ?? device.deviceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              device.deviceId,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ComplianceBadge(status: device.complianceStatus, compact: true),
                _MetaChip(label: device.osBuild ?? 'Unknown OS'),
                _MetaChip(label: _online ? 'Online' : 'Offline'),
              ],
            ),
            const SizedBox(height: 12),
            RiskGauge(score: device.riskScore),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last seen',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  device.lastSeen ?? '-',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: AppColors.textSecondary, fontSize: 11),
      ),
    );
  }
}
