import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/rbac.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/offline_banner.dart';

class CommandCenterScreen extends StatelessWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: PermissionGate(
          requiredRole: UserRole.operator,
          reason: 'Command execution requires Operator or Admin role.',
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const OfflineBanner(),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Command composer',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a device from Fleet to send commands with risk previews and policy checks.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('New command'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: null,
                          child: const Text('View policy preview'),
                        )
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved templates',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _TemplateTile(
                      title: 'Collect sysinfo',
                      subtitle: 'Low risk · Standard privilege',
                    ),
                    _TemplateTile(
                      title: 'Lock screen',
                      subtitle: 'Medium risk · Privileged',
                    ),
                    _TemplateTile(
                      title: 'Retrieve logs',
                      subtitle: 'Low risk · Standard privilege',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent commands',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _CommandRow(
                      title: 'collect_sysinfo',
                      subtitle: 'Device A · Result signed',
                      statusColor: AppColors.accentMint,
                    ),
                    _CommandRow(
                      title: 'lock_screen',
                      subtitle: 'Device C · Awaiting ack',
                      statusColor: AppColors.accentAmber,
                    ),
                    _CommandRow(
                      title: 'download_artifact',
                      subtitle: 'Device B · Failed policy check',
                      statusColor: AppColors.nonCompliant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.title,
    required this.subtitle,
    required this.statusColor,
  });

  final String title;
  final String subtitle;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
