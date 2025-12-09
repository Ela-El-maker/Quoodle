import 'package:flutter/material.dart';

import '../pairing/qr_scan_screen.dart';

class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  static const route = '/devices';

  @override
  Widget build(BuildContext context) {
    final devices = <Map<String, String>>[
      {'name': 'PC001', 'status': 'online'},
      {'name': 'PC002', 'status': 'offline'},
    ];

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
      body: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (_, index) {
          final device = devices[index];
          return ListTile(
            leading: const Icon(Icons.computer),
            title: Text(device['name'] ?? 'Device'),
            subtitle: Text('Status: ${device['status']}'),
          );
        },
      ),
    );
  }
}
