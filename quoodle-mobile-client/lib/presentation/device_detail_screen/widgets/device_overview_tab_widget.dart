import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class DeviceOverviewTabWidget extends StatelessWidget {
  final Map<String, dynamic> device;
  const DeviceOverviewTabWidget({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _buildInfoSection(context, 'Device Identity', [
          _InfoRow('Device ID', device['id'] as String, mono: true),
          _InfoRow('Hostname', device['hostname'] as String, mono: true),
          _InfoRow('IP Address', device['ipAddress'] as String, mono: true),
          _InfoRow('OS', device['os'] as String),
          _InfoRow('Agent Version', 'v${device['agentVersion']}', mono: true),
          _InfoRow('Assigned User', device['assignedUser'] as String),
          _InfoRow('Location', device['location'] as String),
        ]),
        SizedBox(height: 16),
        _buildInfoSection(context, 'Security Posture', [
          _InfoRow(
            'Compliance',
            device['compliance'] == 'compliant'
                ? 'Compliant ✓'
                : 'Non-Compliant ✗',
            valueColor: device['compliance'] == 'compliant'
                ? AppTheme.secondary
                : AppTheme.error,
          ),
          _InfoRow(
            'Policy Hash',
            'abc3f9...e812',
            mono: true,
            valueColor: (device['policySync'] as bool)
                ? AppTheme.secondary
                : AppTheme.warning,
          ),
          _InfoRow(
            'Policy Status',
            (device['policySync'] as bool) ? 'In Sync' : 'Drift Detected',
            valueColor: (device['policySync'] as bool)
                ? AppTheme.secondary
                : AppTheme.warning,
          ),
          _InfoRow(
            'Risk Score',
            '${device['riskScore']} / 100',
            valueColor: (device['riskScore'] as int) >= 70
                ? AppTheme.error
                : AppTheme.warning,
            mono: true,
          ),
          _InfoRow('Attestation', 'Last verified 4h ago'),
        ]),
        SizedBox(height: 16),
        _buildPolicyAlert(context),
        SizedBox(height: 16),
        _buildInfoSection(context, 'Pairing', [
          _InfoRow('Paired At', '2026-01-14  09:22 UTC', mono: true),
          _InfoRow('Session ID', 'sess-9f2a...7c14', mono: true),
          _InfoRow('Fingerprint', 'ed25519:7a3b...ff29', mono: true),
        ]),
      ],
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    String title,
    List<_InfoRow> rows,
  ) {
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
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Divider(height: 1, color: AppTheme.borderLight),
          ...rows.map((row) => _buildInfoRowWidget(context, row)),
        ],
      ),
    );
  }

  Widget _buildInfoRowWidget(BuildContext context, _InfoRow row) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              row.label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: row.mono
                  ? GoogleFonts.ibmPlexMono(
                      fontSize: 12,
                      color: row.valueColor ?? AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    )
                  : GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: row.valueColor ?? AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyAlert(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withAlpha(102), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.warning,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Policy Drift Detected',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warning,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Reported policy hash does not match expected. Run policy_sync to remediate.',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label, value;
  final bool mono;
  final Color? valueColor;
  _InfoRow(this.label, this.value, {this.mono = false, this.valueColor});
}
