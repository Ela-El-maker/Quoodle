import 'package:flutter/material.dart';
import 'dart:async';

import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../services/api_service.dart';
import '../alerts/alerts_screen.dart';
import '../commands/send_command_screen.dart';
import '../commands/command_history_screen.dart';
import '../devices/device_list_screen.dart';
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
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshTelemetry());
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
    return Scaffold(
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
      ),
      body: FutureBuilder<Device>(
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(device.deviceName ?? device.deviceId,
                  style: Theme.of(context).textTheme.headlineSmall),
              if (outOfSync)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Policy Out of Sync: device is reporting a different policy hash than the server expects.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ),
              Text('State: ${device.lifecycleState}'),
              Text('Agent: ${device.agentVersion ?? 'n/a'}'),
              Text('OS: ${device.osBuild ?? 'n/a'}'),
              Text('Compliance: ${device.complianceStatus ?? 'unknown'}'),
              Text('Risk: ${device.riskScore ?? '-'}'),
              const SizedBox(height: 16),
              if (_telemetry != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Telemetry @ ${_telemetry!.timestamp ?? '-'}'),
                    Text(
                        'CPU: ${_telemetry!.cpu ?? '-'} | RAM: ${_telemetry!.ram ?? '-'}'),
                    Text('Disk: ${_telemetry!.diskUsage ?? '-'}'),
                    Text(
                        'Network TX/RX: ${_telemetry!.networkTx ?? '-'} / ${_telemetry!.networkRx ?? '-'}'),
                  ],
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Send Command'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SendCommandScreen(deviceId: device.deviceId),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text('Command History'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CommandHistoryScreen(deviceId: device.deviceId),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.monitor_heart),
                label: const Text('Telemetry History'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TelemetryViewScreen(deviceId: device.deviceId),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.home),
                label: const Text('Back to devices'),
                onPressed: () => Navigator.pushReplacementNamed(
                    context, DeviceListScreen.route),
              ),
            ],
          );
        },
      ),
    );
  }
}
