import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ComplianceBadge extends StatelessWidget {
  const ComplianceBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.complianceColor(status);
    final label = AppColors.complianceLabel(status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 6 : 8,
            height: compact ? 6 : 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11 : 12,
                ),
          ),
        ],
      ),
    );
  }
}
