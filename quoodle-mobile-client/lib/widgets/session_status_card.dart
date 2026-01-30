import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass_card.dart';

class SessionStatusCard extends StatelessWidget {
  const SessionStatusCard({
    super.key,
    required this.role,
    required this.mfaEnabled,
    required this.sessionExpiresIn,
  });

  final String role;
  final bool mfaEnabled;
  final Duration sessionExpiresIn;

  @override
  Widget build(BuildContext context) {
    final expiresText = _formatDuration(sessionExpiresIn);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: AppColors.accentMint),
              const SizedBox(width: 8),
              Text(
                'Session status',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusRow(label: 'Role', value: role),
          _StatusRow(label: 'MFA', value: mfaEnabled ? 'Enabled' : 'Required'),
          _StatusRow(label: 'TTL', value: expiresText),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
