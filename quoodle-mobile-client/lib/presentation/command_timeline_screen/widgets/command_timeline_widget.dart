import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class CommandTimelineWidget extends StatefulWidget {
  final CommandStatus currentStatus;
  final Map<String, dynamic> command;

  const CommandTimelineWidget({
    super.key,
    required this.currentStatus,
    required this.command,
  });

  @override
  State<CommandTimelineWidget> createState() => _CommandTimelineWidgetState();
}

class _CommandTimelineWidgetState extends State<CommandTimelineWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = _buildStages(widget.command, widget.currentStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXECUTION TIMELINE',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(stages.length, (i) {
            final stage = stages[i];
            final isLast = i == stages.length - 1;
            return _TimelineStageRow(
              stage: stage,
              isLast: isLast,
              isActive: stage.isActive,
              pulseAnimation: _pulseAnimation,
            );
          }),
        ],
      ),
    );
  }

  List<_TimelineStage> _buildStages(
    Map<String, dynamic> cmd,
    CommandStatus status,
  ) {
    final statusOrder = [
      CommandStatus.queued,
      CommandStatus.dispatched,
      CommandStatus.acked,
      CommandStatus.executing,
      CommandStatus.completed,
    ];

    final currentIndex = statusOrder.indexOf(status);
    // If failed, replace completed with failed
    final effectiveOrder = status == CommandStatus.failed
        ? [...statusOrder.sublist(0, 4), CommandStatus.failed]
        : status == CommandStatus.expired
            ? [...statusOrder.sublist(0, 4), CommandStatus.expired]
            : statusOrder;

    final timestamps = {
      CommandStatus.queued: cmd['queuedAt'] as String?,
      CommandStatus.dispatched: cmd['dispatchedAt'] as String?,
      CommandStatus.acked: cmd['ackedAt'] as String?,
      CommandStatus.executing: cmd['executingAt'] as String?,
      CommandStatus.completed: cmd['completedAt'] as String?,
      CommandStatus.failed: cmd['completedAt'] as String?,
      CommandStatus.expired: cmd['completedAt'] as String?,
    };

    final labels = {
      CommandStatus.queued: (
        'Queued',
        'Accepted by control plane',
        Icons.inbox_rounded,
      ),
      CommandStatus.dispatched: (
        'Dispatched',
        'Forwarded to FastAPI gateway',
        Icons.send_rounded,
      ),
      CommandStatus.acked: (
        'Acknowledged',
        'Agent confirmed receipt',
        Icons.handshake_rounded,
      ),
      CommandStatus.executing: (
        'Executing',
        'Running on endpoint',
        Icons.play_arrow_rounded,
      ),
      CommandStatus.completed: (
        'Completed',
        'Execution successful',
        Icons.check_circle_rounded,
      ),
      CommandStatus.failed: ('Failed', 'Execution error', Icons.cancel_rounded),
      CommandStatus.expired: (
        'Expired',
        'Command TTL exceeded',
        Icons.timer_off_rounded,
      ),
    };

    return List.generate(effectiveOrder.length, (i) {
      final s = effectiveOrder[i];
      final info = labels[s]!;
      final isDone = i < currentIndex ||
          (i == currentIndex &&
              (status == CommandStatus.completed ||
                  status == CommandStatus.failed ||
                  status == CommandStatus.expired));
      final isActive = i == currentIndex &&
          status != CommandStatus.completed &&
          status != CommandStatus.failed &&
          status != CommandStatus.expired;

      String? ts = timestamps[s];
      if (ts != null && ts.contains('T')) {
        // Format ISO to HH:mm:ss
        try {
          final dt = DateTime.parse(ts).toLocal();
          ts =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
        } catch (_) {}
      }

      return _TimelineStage(
        status: s,
        label: info.$1,
        description: info.$2,
        icon: info.$3,
        timestamp: isDone || isActive ? ts : null,
        isDone: isDone,
        isActive: isActive,
        isPending: !isDone && !isActive,
      );
    });
  }
}

class _TimelineStage {
  final CommandStatus status;
  final String label, description;
  final IconData icon;
  final String? timestamp;
  final bool isDone, isActive, isPending;

  const _TimelineStage({
    required this.status,
    required this.label,
    required this.description,
    required this.icon,
    required this.timestamp,
    required this.isDone,
    required this.isActive,
    required this.isPending,
  });
}

class _TimelineStageRow extends StatelessWidget {
  final _TimelineStage stage;
  final bool isLast;
  final bool isActive;
  final Animation<double> pulseAnimation;

  const _TimelineStageRow({
    required this.stage,
    required this.isLast,
    required this.isActive,
    required this.pulseAnimation,
  });

  Color get _stageColor {
    if (stage.isDone) {
      if (stage.status == CommandStatus.failed) return AppTheme.error;
      if (stage.status == CommandStatus.expired) return AppTheme.statusOffline;
      return AppTheme.secondary;
    }
    if (stage.isActive) return AppTheme.warning;
    return AppTheme.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: indicator + connector
        SizedBox(
          width: 40,
          child: Column(
            children: [
              // Stage indicator
              AnimatedBuilder(
                animation: pulseAnimation,
                builder: (_, child) {
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: stage.isDone
                          ? _stageColor.withAlpha(38)
                          : stage.isActive
                              ? _stageColor.withAlpha(
                                  (255 * (0.1 + 0.15 * pulseAnimation.value))
                                      .round(),
                                )
                              : AppTheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: stage.isPending
                            ? AppTheme.border
                            : _stageColor.withAlpha(
                                (255 *
                                        (stage.isActive
                                            ? pulseAnimation.value
                                            : 1.0))
                                    .round(),
                              ),
                        width: stage.isActive ? 2 : 1.5,
                      ),
                    ),
                    child: Icon(
                      stage.icon,
                      size: 14,
                      color: stage.isPending
                          ? AppTheme.textMuted.withAlpha(102)
                          : _stageColor,
                    ),
                  );
                },
              ),
              // Connector line
              if (!isLast)
                Container(
                  width: 2,
                  height: 32,
                  color: stage.isDone
                      ? _stageColor.withAlpha(102)
                      : AppTheme.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Right: content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      stage.label,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: stage.isDone || stage.isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: stage.isPending
                            ? AppTheme.textMuted.withAlpha(128)
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (stage.timestamp != null)
                      Text(
                        stage.timestamp!,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          color: _stageColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  stage.description,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: stage.isPending
                        ? AppTheme.textMuted.withAlpha(102)
                        : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
