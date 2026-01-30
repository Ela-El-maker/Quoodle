import 'package:flutter/material.dart';

import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../utils/rbac.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/session_status_card.dart';
import '../auth/login_screen.dart';
import '../system/system_status_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _highRiskAlerts = true;

  @override
  Widget build(BuildContext context) {
    final userId = SessionStore.userId ?? 'unknown';
    final roleLabel = Rbac.label(Rbac.currentRole());
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Trust')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const OfflineBanner(),
            SessionStatusCard(
              role: roleLabel,
              mfaEnabled: true,
              sessionExpiresIn: const Duration(hours: 3, minutes: 18),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'User ID', value: userId),
                  _InfoRow(label: 'Role', value: roleLabel),
                  _InfoRow(label: 'Trust', value: 'MFA enforced'),
                ],
              ),
            ),
            if (Rbac.hasAtLeast(UserRole.admin)) ...[
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Access policy rollouts, compliance rules, and fleet-wide actions from the web console.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _pushNotifications,
                    onChanged: (value) =>
                        setState(() => _pushNotifications = value),
                    title: const Text('Push notifications'),
                  ),
                  SwitchListTile.adaptive(
                    value: _highRiskAlerts,
                    onChanged: (value) =>
                        setState(() => _highRiskAlerts = value),
                    title: const Text('High-risk command alerts'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session controls',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Revoke sessions and rotate keys from the control plane.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SystemStatusScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_heart),
                    label: const Text('System status'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await SessionStore.clear();
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                          context, LoginScreen.route, (_) => false);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
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
