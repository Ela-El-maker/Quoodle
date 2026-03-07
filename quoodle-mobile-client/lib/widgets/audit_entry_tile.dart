import 'package:flutter/material.dart';

import '../models/audit_entry.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

class AuditEntryTile extends StatefulWidget {
  const AuditEntryTile({super.key, required this.entry});

  final AuditEntry entry;

  @override
  State<AuditEntryTile> createState() => _AuditEntryTileState();
}

class _AuditEntryTileState extends State<AuditEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: const BoxDecoration(
                    color: AppColors.accentBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.entry.summary,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.entry.timestamp ?? '-'} • ${widget.entry.eventType}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            _DetailRow(label: 'Hash', value: widget.entry.hash ?? '-'),
            _DetailRow(label: 'Previous', value: widget.entry.prevHash ?? '-'),
            _DetailRow(
                label: 'Signature', value: widget.entry.signature ?? '-'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentMint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Verification intact',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.accentMint, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
