import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class RiskGauge extends StatelessWidget {
  const RiskGauge({super.key, required this.score});

  final num? score;

  @override
  Widget build(BuildContext context) {
    final double value = (score ?? 0).toDouble().clamp(0, 100).toDouble();
    final color = AppColors.riskColor(value);
    final label = _riskLabel(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Risk score',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 10,
            backgroundColor: AppColors.surfaceRaised,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(0)} / 100',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _riskLabel(double value) {
    if (value >= 80) return 'Needs attention';
    if (value >= 60) return 'Elevated';
    if (value >= 35) return 'Observed';
    return 'Stable';
  }
}
