import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../services/api_service.dart';
import '../alerts/alerts_screen.dart';
import '../commands/send_command_screen.dart';
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
  late Future<TelemetrySnapshot> _telemetryFuture;

  @override
  void initState() {
    super.initState();
    _deviceFuture = _api.fetchDevice(widget.deviceId);
    _telemetryFuture = _api.fetchLatestTelemetry(widget.deviceId);
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
              MaterialPageRoute(builder: (_) => AlertsScreen(deviceId: widget.deviceId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => UpdateListScreen(deviceId: widget.deviceId)),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(device.deviceName ?? device.deviceId, style: Theme.of(context).textTheme.headlineSmall),
              Text('State: ${device.lifecycleState}'),
              Text('Agent: ${device.agentVersion ?? 'n/a'}'),
              Text('OS: ${device.osBuild ?? 'n/a'}'),
              Text('Compliance: ${device.complianceStatus ?? 'unknown'}'),
              Text('Risk: ${device.riskScore ?? '-'}'),
              const SizedBox(height: 16),
              FutureBuilder<TelemetrySnapshot>(
                future: _telemetryFuture,
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox();
                  final tel = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Telemetry @ ${tel.timestamp ?? '-'}'),
                      Text('CPU: ${tel.cpu ?? '-'} | RAM: ${tel.ram ?? '-'}'),
                      Text('Disk: ${tel.diskUsage ?? '-'}'),
                      Text('Network TX/RX: ${tel.networkTx ?? '-'} / ${tel.networkRx ?? '-'}'),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Send Command'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SendCommandScreen(deviceId: device.deviceId),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.monitor_heart),
                label: const Text('Telemetry History'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TelemetryViewScreen(deviceId: device.deviceId),
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.home),
                label: const Text('Back to devices'),
                onPressed: () => Navigator.pushReplacementNamed(context, DeviceListScreen.route),
              ),
            ],
          );
        },
      ),
    );
  }
}
