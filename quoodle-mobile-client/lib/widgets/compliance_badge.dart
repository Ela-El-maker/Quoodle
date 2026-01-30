import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ComplianceBadge extends StatefulWidget {
  const ComplianceBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String? status;
  final bool compact;

  @override
  State<ComplianceBadge> createState() => _ComplianceBadgeState();
}

class _ComplianceBadgeState extends State<ComplianceBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulse = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (_shouldPulse(widget.status)) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ComplianceBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldPulse(widget.status)) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  bool _shouldPulse(String? status) {
    final value = (status ?? '').toLowerCase();
    return value.contains('degrad') ||
        value.contains('non') ||
        value.contains('fail') ||
        value.contains('quarantine');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.complianceColor(widget.status);
    final label = AppColors.complianceLabel(widget.status);
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 8 : 12,
          vertical: widget.compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: widget.compact ? 6 : 8,
              height: widget.compact ? 6 : 8,
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
                    fontSize: widget.compact ? 11 : 12,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
