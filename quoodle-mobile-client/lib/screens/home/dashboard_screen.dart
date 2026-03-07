import 'package:flutter/material.dart';

import '../../models/alert.dart';
import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/fleet_stats_header.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';
import '../audit/audit_ledger_screen.dart';
import '../devices/device_detail_screen.dart';
import '../devices/device_list_screen.dart';
import '../pairing/qr_scan_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait([
      _api.fetchDevices(),
      _api.fetchAlerts(),
    ]);
    return _DashboardData(
      devices: results[0] as List<Device>,
      alerts: results[1] as List<AlertItem>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to load your overview',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              final activeDevices = data.devices
                  .where((device) =>
                      device.lifecycleState.toLowerCase().contains('online') ||
                      device.lifecycleState.toLowerCase().contains('active'))
                  .length;
              final attention = data.devices
                  .where((device) => (device.riskScore ?? 0) >= 60)
                  .toList();
              final recentAlerts = data.alerts.take(3).toList();

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  const OfflineBanner(),
                  Text(greeting,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    '$activeDevices devices active. Verification remains intact across your fleet.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  FleetStatsHeader(devices: data.devices),
                  const SizedBox(height: 24),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Needs attention',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          'A small queue of items worth reviewing next.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (attention.isEmpty && recentAlerts.isEmpty)
                          Text(
                            'Everything looks calm right now.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        else ...[
                          ...attention.take(2).map(
                                (device) => _AttentionRow(
                                  title: device.deviceName ?? device.deviceId,
                                  subtitle:
                                      'Risk score ${device.riskScore?.toStringAsFixed(0) ?? '-'}',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DeviceDetailScreen(
                                          deviceId: device.deviceId),
                                    ),
                                  ),
                                ),
                              ),
                          ...recentAlerts.map(
                            (alert) => _AttentionRow(
                              title: alert.message ?? 'Alert',
                              subtitle:
                                  '${alert.deviceId ?? 'Fleet'} • ${alert.timestamp ?? '-'}',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const AuditLedgerScreen()),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick actions',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, QrScanScreen.route),
                          child: const Text('Pair a device'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DeviceListScreen()),
                          ),
                          child: const Text('Open devices'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({required this.devices, required this.alerts});

  final List<Device> devices;
  final List<AlertItem> alerts;
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
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
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
