import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../theme/app_colors.dart';
import '../../widgets/compliance_badge.dart';
import '../../widgets/glass_card.dart';
import '../pairing/qr_scan_screen.dart';
import '../updates/update_list_screen.dart';

class DeviceComplianceScreen extends StatelessWidget {
  const DeviceComplianceScreen({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Compliance')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.deviceName ?? device.deviceId,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ComplianceBadge(status: device.complianceStatus),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Compliance', value: device.complianceStatus ?? 'unknown'),
                  _InfoRow(label: 'Risk score', value: device.riskScore?.toStringAsFixed(0) ?? '-'),
                  _InfoRow(label: 'Policy hash', value: device.policyHash ?? '-'),
                  _InfoRow(label: 'Reported hash', value: device.reportedPolicyHash ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remediation steps',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.verified_user,
                    title: 'Run attestation now',
                    subtitle: 'Re-verify device integrity and keys.',
                    onTap: () => _showAttestationDialog(context),
                  ),
                  _ActionTile(
                    icon: Icons.qr_code,
                    title: 'Re-pair device',
                    subtitle: 'Refresh device identity and trust binding.',
                    onTap: () => Navigator.pushNamed(context, QrScanScreen.route),
                  ),
                  _ActionTile(
                    icon: Icons.system_update_alt,
                    title: 'Update agent',
                    subtitle: 'Ensure the latest secure agent is installed.',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UpdateListScreen(deviceId: device.deviceId),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.accentCyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

void _showAttestationDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Attestation required'),
      content: const Text(
          'This action must be triggered from the agent. Ask the device owner to run a local attestation check.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        )
      ],
    ),
  );
}
