import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

class FleetStatsHeader extends StatelessWidget {
  const FleetStatsHeader({super.key, required this.devices});

  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    final total = devices.length;
    final online = devices
        .where((d) => d.lifecycleState.toLowerCase().contains('online'))
        .length;
    final atRisk = devices.where((d) => (d.riskScore ?? 0) >= 60).length;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatBlock(
            label: 'Total',
            value: total.toString(),
            accent: AppColors.accentCyan,
          ),
          _StatBlock(
            label: 'Online',
            value: online.toString(),
            accent: AppColors.accentMint,
          ),
          _StatBlock(
            label: 'At risk',
            value: atRisk.toString(),
            accent: AppColors.riskHigh,
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: AppColors.textSecondary),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            value,
            key: ValueKey<String>(value),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: accent),
          ),
        ),
      ],
    );
  }
}
