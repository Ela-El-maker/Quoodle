import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CommandStatusStepper extends StatelessWidget {
  const CommandStatusStepper({
    super.key,
    required this.currentState,
    this.errorMessage,
  });

  final String? currentState;
  final String? errorMessage;

  static const List<String> _states = [
    'queued',
    'acknowledged',
    'executing',
    'completed',
  ];

  @override
  Widget build(BuildContext context) {
    final normalized = (currentState ?? '').toLowerCase();
    final currentIndex = _states.indexOf(normalized);
    final failed = normalized == 'failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _states.length; i++)
          _StepRow(
            label: _labelFor(_states[i]),
            active: failed ? i < 3 : i <= currentIndex,
            isCurrent: !failed && i == currentIndex,
            isLast: i == _states.length - 1,
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorMessage == null || errorMessage!.isEmpty
                  ? 'The command did not complete.'
                  : errorMessage!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.nonCompliant),
            ),
          ),
      ],
    );
  }

  String _labelFor(String state) {
    switch (state) {
      case 'queued':
        return 'Queued';
      case 'acknowledged':
        return 'Delivered';
      case 'executing':
        return 'Running';
      case 'completed':
        return 'Complete';
      default:
        return state;
    }
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.active,
    required this.isCurrent,
    required this.isLast,
  });

  final String label;
  final bool active;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentBlue : AppColors.glassBorder;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: active ? color : AppColors.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: color),
              ),
              child: active
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 1,
                height: 26,
                color: AppColors.glassBorder,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isCurrent
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
                ),
          ),
        ),
      ],
    );
  }
}
