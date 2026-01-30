import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';

class SystemStatusScreen extends StatelessWidget {
  const SystemStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Status')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const OfflineBanner(),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Control plane',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _StatusRow(label: 'API', value: 'Operational'),
                  _StatusRow(label: 'Gateway', value: 'Operational'),
                  _StatusRow(label: 'Queue depth', value: '12'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connectivity',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _StatusRow(label: 'WS sessions', value: '48 active'),
                  _StatusRow(label: 'Agent backlog', value: '3 pending'),
                  _StatusRow(label: 'Heartbeat lag', value: '2s avg'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Data services',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _StatusRow(label: 'Redis', value: 'Healthy'),
                  _StatusRow(label: 'Workers', value: '9 online'),
                  _StatusRow(label: 'Audit ledger', value: 'Syncing'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
