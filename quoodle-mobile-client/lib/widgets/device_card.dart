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

  IconData get _osIcon {
    final value = (device.osBuild ?? '').toLowerCase();
    if (value.contains('windows')) return Icons.window_outlined;
    if (value.contains('linux')) return Icons.laptop_chromebook_outlined;
    if (value.contains('mac')) return Icons.laptop_mac_outlined;
    return Icons.devices_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.complianceColor(device.complianceStatus);
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: 1,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_osIcon, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName ?? device.deviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.deviceId,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _online ? AppColors.accentMint : AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ComplianceBadge(status: device.complianceStatus, compact: true),
                _MetaChip(label: _online ? 'Active' : 'Offline'),
              ],
            ),
            const SizedBox(height: 16),
            RiskGauge(score: device.riskScore),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InfoColumn(
                      label: 'OS', value: device.osBuild ?? 'Unknown'),
                ),
                Expanded(
                  child: _InfoColumn(
                      label: 'Last seen', value: device.lastSeen ?? '-'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Verification intact',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
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
