import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/rbac.dart';
import 'glass_card.dart';

class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.requiredRole,
    required this.child,
    this.reason,
  });

  final UserRole requiredRole;
  final Widget child;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final allowed = Rbac.hasAtLeast(requiredRole);
    if (allowed) return child;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock, color: AppColors.accentAmber),
              const SizedBox(width: 8),
              Text(
                'Action restricted',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason ??
                'This action requires ${Rbac.label(requiredRole)} role or higher.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            'Current role: ${Rbac.label(Rbac.currentRole())}',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
