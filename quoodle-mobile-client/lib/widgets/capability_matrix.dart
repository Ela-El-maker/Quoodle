import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass_card.dart';

class CapabilityRow {
  const CapabilityRow({
    required this.capability,
    required this.supported,
    required this.privilege,
    required this.riskTier,
  });

  final String capability;
  final bool supported;
  final String privilege;
  final String riskTier;
}

class CapabilityMatrix extends StatelessWidget {
  const CapabilityMatrix({super.key, required this.rows});

  final List<CapabilityRow> rows;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capabilities',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...rows.map((row) => _CapabilityRowItem(row: row)),
        ],
      ),
    );
  }
}

class _CapabilityRowItem extends StatelessWidget {
  const _CapabilityRowItem({required this.row});

  final CapabilityRow row;

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColor(row.riskTier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.capability,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  row.supported ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color:
                      row.supported ? AppColors.accentMint : AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  row.supported ? 'Yes' : 'No',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.privilege,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: riskColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  row.riskTier,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: riskColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _riskColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'critical':
        return AppColors.riskCritical;
      case 'high':
        return AppColors.riskHigh;
      case 'medium':
        return AppColors.riskMedium;
      default:
        return AppColors.riskLow;
    }
  }
}
