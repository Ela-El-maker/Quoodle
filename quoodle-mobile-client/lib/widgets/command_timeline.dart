import 'package:flutter/material.dart';

import '../models/command.dart';
import '../theme/app_colors.dart';

class CommandTimeline extends StatelessWidget {
  const CommandTimeline({super.key, required this.command});

  final CommandState command;

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps(command);
    return Column(
      children: steps
          .map((step) => _TimelineRow(
                title: step.title,
                subtitle: step.subtitle,
                status: step.status,
              ))
          .toList(),
    );
  }

  List<_TimelineStep> _buildSteps(CommandState command) {
    final state = (command.state ?? '').toLowerCase();
    final queuedAt = command.queuedAt ?? '-';
    final completedAt = command.completedAt ?? '-';

    final dispatched = state.contains('dispatched') || state.contains('acked');
    final acked = state.contains('ack');
    final completed = state.contains('completed') || state.contains('failed');

    return [
      _TimelineStep(
        title: 'INTENT',
        subtitle: 'Created $queuedAt',
        status: _StepStatus.complete,
      ),
      _TimelineStep(
        title: 'DISPATCHED',
        subtitle: dispatched ? 'Sent to gateway' : 'Pending dispatch',
        status: dispatched ? _StepStatus.complete : _StepStatus.pending,
      ),
      _TimelineStep(
        title: 'ACK',
        subtitle: acked ? 'Agent acknowledged' : 'Awaiting ack',
        status: acked
            ? _StepStatus.complete
            : (dispatched ? _StepStatus.active : _StepStatus.pending),
      ),
      _TimelineStep(
        title: 'RESULT',
        subtitle: completed ? 'Completed $completedAt' : 'Awaiting result',
        status: completed
            ? (state.contains('failed')
                ? _StepStatus.failed
                : _StepStatus.complete)
            : (acked ? _StepStatus.active : _StepStatus.pending),
      ),
    ];
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 28,
                color: color.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(_StepStatus status) {
    switch (status) {
      case _StepStatus.complete:
        return AppColors.accentMint;
      case _StepStatus.active:
        return AppColors.accentCyan;
      case _StepStatus.failed:
        return AppColors.nonCompliant;
      case _StepStatus.pending:
        return AppColors.textMuted;
    }
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final _StepStatus status;
}

enum _StepStatus { pending, active, complete, failed }
