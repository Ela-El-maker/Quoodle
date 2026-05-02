import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class CommandAuditWidget extends StatelessWidget {
  final Map<String, dynamic> command;

  const CommandAuditWidget({super.key, required this.command});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 15,
                  color: AppTheme.textMuted,
                ),
                SizedBox(width: 8),
                Text(
                  'AUDIT & SIGNATURES',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.borderLight),
          _AuditRow(label: 'Command ID', value: command['id'] as String),
          _AuditRow(
            label: 'Initiator',
            value: '${command['initiator']} (${command['role']})',
          ),
          _AuditRow(
            label: 'Device',
            value: '${command['deviceName']} · ${command['deviceId']}',
          ),
          _AuditRow(
            label: 'Policy Decision',
            value: (command['policyDecision'] as String).toUpperCase(),
            valueColor: AppTheme.secondary,
          ),
          _AuditRow(label: 'Policy Version', value: 'v1.0.4', mono: true),
          _AuditRow(
            label: 'Request Sig',
            value: 'sig_req:7f3a9e...c114',
            mono: true,
          ),
          _AuditRow(
            label: 'Envelope Sig',
            value: 'sig_env:2b8f1d...a907',
            mono: true,
          ),
          _AuditRow(label: 'Server Seq', value: '#1094', mono: true),
          _AuditRow(
            label: 'Queued At',
            value: command['queuedAt'] as String,
            mono: true,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final String label, value;
  final bool mono;
  final bool isLast;
  final Color? valueColor;

  const _AuditRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.isLast = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: AppTheme.borderLight, width: 1),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      color: valueColor ?? AppTheme.textSecondary,
                    )
                  : GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: valueColor ?? AppTheme.textSecondary,
                    ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
