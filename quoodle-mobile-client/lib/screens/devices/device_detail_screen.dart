import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Telemetry'),
              Tab(text: 'Commands'),
              Tab(text: 'Alerts'),
              Tab(text: 'Updates'),
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
              final reported =
                  device.reportedPolicyHash ?? _telemetry?.policyHash;
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
                  _TelemetryTab(
                      deviceId: device.deviceId, telemetry: _telemetry),
                  _CommandsTab(deviceId: device.deviceId),
                  _AlertsTab(deviceId: device.deviceId),
                  _UpdatesTab(deviceId: device.deviceId),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.deviceName ?? device.deviceId,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ComplianceBadge(status: device.complianceStatus),
                  _SoftPill(label: device.lifecycleState),
                ],
              ),
              const SizedBox(height: 20),
              RiskGauge(score: device.riskScore),
              if (outOfSync)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Policy needs review. The device is reporting a different policy hash than the control plane.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device health',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _DetailRow(label: 'Last seen', value: device.lastSeen ?? '-'),
              _DetailRow(
                  label: 'Agent version', value: device.agentVersion ?? 'n/a'),
              _DetailRow(label: 'OS build', value: device.osBuild ?? 'n/a'),
              _DetailRow(label: 'Verification', value: 'Intact'),
            ],
          ),
        ),
        if (telemetry != null) ...[
          const SizedBox(height: 16),
          LiveTelemetryCard(snapshot: telemetry!),
        ],
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Security state',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                'Capabilities are available from the control plane, and command execution is verified on the endpoint before anything runs.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceComplianceScreen(device: device),
                  ),
                ),
                child: const Text('Review compliance'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TelemetryTab extends StatelessWidget {
  const _TelemetryTab({required this.deviceId, required this.telemetry});

  final String deviceId;
  final TelemetrySnapshot? telemetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        if (telemetry != null) LiveTelemetryCard(snapshot: telemetry!),
        if (telemetry == null)
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Text('Waiting for live telemetry.',
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('History', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Open the recent telemetry timeline to review calm, high-level trends.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TelemetryViewScreen(deviceId: deviceId),
                  ),
                ),
                child: const Text('Open telemetry history'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommandsTab extends StatelessWidget {
  const _CommandsTab({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Command flow',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Choose a command, review its risk, and confirm execution in a single calm flow.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SendCommandScreen(deviceId: deviceId),
                  ),
                ),
                child: const Text('Send command'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent activity',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Command acknowledgements and results stay attached to the device timeline.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CommandHistoryScreen(deviceId: deviceId),
                  ),
                ),
                child: const Text('Open command history'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertsTab extends StatelessWidget {
  const _AlertsTab({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alerts', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Review only the alerts connected to this device and acknowledge them once understood.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlertsScreen(deviceId: deviceId),
                  ),
                ),
                child: const Text('Open alerts'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Updates', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Keep software rollouts readable and predictable with a single quiet timeline.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UpdateListScreen(deviceId: deviceId),
                  ),
                ),
                child: const Text('Open update history'),
              ),
            ],
          ),
        ),
      ],
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
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  const _SoftPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
