import 'package:flutter/material.dart';

import '../models/telemetry.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

class LiveTelemetryCard extends StatelessWidget {
  const LiveTelemetryCard({super.key, required this.snapshot});

  final TelemetrySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Telemetry',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.timestamp ?? 'No timestamp',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          _MetricRow(label: 'CPU', value: snapshot.cpu ?? '-'),
          _MetricRow(label: 'RAM', value: snapshot.ram ?? '-'),
          _MetricRow(label: 'Disk', value: snapshot.diskUsage ?? '-'),
          _MetricRow(
            label: 'Network',
            value: '${snapshot.networkTx ?? '-'} / ${snapshot.networkRx ?? '-'}',
          ),
          if (snapshot.riskScore != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Telemetry risk',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  snapshot.riskScore!.toStringAsFixed(0),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.riskColor(snapshot.riskScore),
                      ),
                )
              ],
            ),
          ]
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

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
