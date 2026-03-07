import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/capability_matrix.dart';
import '../../widgets/compliance_badge.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/live_telemetry_card.dart';
import '../../widgets/risk_gauge.dart';
import '../alerts/alerts_screen.dart';
import '../commands/command_history_screen.dart';
import '../commands/send_command_screen.dart';
import '../compliance/device_compliance_screen.dart';
import '../telemetry/telemetry_view.dart';
import '../updates/update_list_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  static const route = '/device';
  final String deviceId;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final ApiService _api = ApiService();
  late Future<Device> _deviceFuture;
  TelemetrySnapshot? _telemetry;
  Timer? _timer;
  bool _telemetryInFlight = false;

  @override
  void initState() {
    super.initState();
    _deviceFuture = _api.fetchDevice(widget.deviceId);
    _refreshTelemetry();
    _timer =
        Timer.periodic(const Duration(seconds: 3), (_) => _refreshTelemetry());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTelemetry() async {
    if (_telemetryInFlight) return;
    _telemetryInFlight = true;
    try {
      final latest = await _api.fetchLatestTelemetry(widget.deviceId);
      if (!mounted) return;
      setState(() => _telemetry = latest);
    } catch (_) {
      // ignore network errors for live polling
    } finally {
      _telemetryInFlight = false;
    }
  }

  List<CapabilityRow> _capabilityRows(Device device) {
    return const [
      CapabilityRow(
        capability: 'lock_screen',
        supported: true,
        privilege: 'Privileged',
        riskTier: 'Medium',
      ),
      CapabilityRow(
        capability: 'collect_sysinfo',
        supported: true,
        privilege: 'Standard',
        riskTier: 'Low',
      ),
      CapabilityRow(
        capability: 'download_artifact',
        supported: true,
        privilege: 'Standard',
        riskTier: 'Low',
      ),
      CapabilityRow(
        capability: 'wipe_device',
        supported: false,
        privilege: 'Privileged',
        riskTier: 'Critical',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device Detail'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlertsScreen(deviceId: widget.deviceId)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => UpdateListScreen(deviceId: widget.deviceId)),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Capabilities'),
              Tab(text: 'Telemetry'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          child: FutureBuilder<Device>(
            future: _deviceFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final device = snapshot.data!;
              final expected = device.policyHash;
              final reported = device.reportedPolicyHash ?? _telemetry?.policyHash;
              final outOfSync = (device.policyInSync == false) ||
                  (expected != null &&
                      expected.isNotEmpty &&
                      reported != null &&
                      reported.isNotEmpty &&
                      expected != reported);
              return TabBarView(
                children: [
                  _OverviewTab(
                    device: device,
                    telemetry: _telemetry,
                    outOfSync: outOfSync,
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: CapabilityMatrix(rows: _capabilityRows(device)),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_telemetry != null)
                          LiveTelemetryCard(snapshot: _telemetry!),
                        const SizedBox(height: 16),
                        GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Telemetry history',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Review hourly trends and anomalies from the last 24 hours.',
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
                                    builder: (_) => TelemetryViewScreen(
                                        deviceId: device.deviceId),
                                  ),
                                ),
                                icon: const Icon(Icons.monitor_heart),
                                label: const Text('Open telemetry history'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Command activity',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'View command intents, acknowledgements, and results for this device.',
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
                                    builder: (_) => CommandHistoryScreen(
                                        deviceId: device.deviceId),
                                  ),
                                ),
                                icon: const Icon(Icons.list_alt),
                                label: const Text('Open command history'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SendCommandScreen(deviceId: widget.deviceId),
            ),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Send Command'),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.device,
    required this.telemetry,
    required this.outOfSync,
  });

  final Device device;
  final TelemetrySnapshot? telemetry;
  final bool outOfSync;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName ?? device.deviceId,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                ComplianceBadge(status: device.complianceStatus),
                const SizedBox(height: 12),
                if (outOfSync)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.nonCompliant.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.nonCompliant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Policy out of sync. Device reports a different policy hash than the control plane.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.nonCompliant),
                    ),
                  ),
                const SizedBox(height: 12),
                _DetailRow(label: 'Lifecycle', value: device.lifecycleState),
                _DetailRow(label: 'Agent', value: device.agentVersion ?? 'n/a'),
                _DetailRow(label: 'OS build', value: device.osBuild ?? 'n/a'),
                _DetailRow(
                    label: 'Risk',
                    value: device.riskScore?.toStringAsFixed(0) ?? '-'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DeviceComplianceScreen(device: device),
                      ),
                    ),
                    icon: const Icon(Icons.shield),
                    label: const Text('View compliance'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: RiskGauge(score: device.riskScore),
          ),
          if (telemetry != null) ...[
            const SizedBox(height: 16),
            LiveTelemetryCard(snapshot: telemetry!),
          ]
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
