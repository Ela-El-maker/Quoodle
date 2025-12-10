import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/api_service.dart';
import '../pairing/qr_scan_screen.dart';
import 'device_detail_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  static const route = '/devices';

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final ApiService _api = ApiService();
  late Future<List<Device>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = _api.fetchDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.pushNamed(context, QrScanScreen.route),
          ),
        ],
      ),
      body: FutureBuilder<List<Device>>(
        future: _devices,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final devices = snapshot.data!;
          if (devices.isEmpty) {
            return const Center(child: Text('No devices paired yet'));
          }
          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (_, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.computer),
                title: Text(device.deviceName ?? device.deviceId),
                subtitle: Text('State: ${device.lifecycleState} • Last seen: ${device.lastSeen ?? '-'}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceDetailScreen(deviceId: device.deviceId),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
