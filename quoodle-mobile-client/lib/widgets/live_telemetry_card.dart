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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live telemetry',
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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TelemetryMeter(
                  label: 'CPU',
                  valueLabel: snapshot.cpu ?? '-',
                  progress: _parsePercent(snapshot.cpu),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TelemetryMeter(
                  label: 'RAM',
                  valueLabel: snapshot.ram ?? '-',
                  progress: _parsePercent(snapshot.ram),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TelemetryMeter(
                  label: 'Disk',
                  valueLabel: snapshot.diskUsage ?? '-',
                  progress: _parsePercent(snapshot.diskUsage),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TelemetryMeter(
                  label: 'Network',
                  valueLabel:
                      '${snapshot.networkTx ?? '-'} / ${snapshot.networkRx ?? '-'}',
                  progress: null,
                ),
              ),
            ],
          ),
          if (snapshot.riskScore != null) ...[
            const SizedBox(height: 20),
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

  double? _parsePercent(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll('%', '').trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    return (parsed / 100).clamp(0, 1);
  }
}

class _TelemetryMeter extends StatelessWidget {
  const _TelemetryMeter({
    required this.label,
    required this.valueLabel,
    this.progress,
  });

  final String label;
  final String valueLabel;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            valueLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
          ],
        ],
      ),
    );
  }
}
