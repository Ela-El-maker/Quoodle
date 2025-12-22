import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../services/session_store.dart';

class UnpairedDevicesScreen extends StatefulWidget {
  const UnpairedDevicesScreen({super.key});

  @override
  State<UnpairedDevicesScreen> createState() => _UnpairedDevicesScreenState();
}

class _UnpairedDevicesScreenState extends State<UnpairedDevicesScreen> {
  final ApiService _api = ApiService();
  late Future<List<Device>> _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _devices = _load();
  }

  Future<List<Device>> _load() async {
    final userId = SessionStore.userId;
    final sessionId = SessionStore.sessionId;
    if (userId == null || sessionId == null) {
      throw Exception('Not logged in');
    }
    return _api.fetchUnpairedDevices(userId: userId, sessionId: sessionId);
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
      _devices = _load();
    });
    await _devices;
  }

  Future<void> _claim(Device d) async {
    final userId = SessionStore.userId;
    final sessionId = SessionStore.sessionId;
    if (userId == null || sessionId == null) return;

    setState(() => _error = null);
    try {
      await _api.claimDevice(
          deviceId: d.deviceId, userId: userId, sessionId: sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Device claimed')));
      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unpaired Devices'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<Device>>(
        future: _devices,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              if (list.isEmpty)
                const Text('No unpaired devices found.')
              else
                ...list.map(
                  (d) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.computer),
                      title: Text(d.deviceName ?? d.deviceId),
                      subtitle: Text(
                          'State: ${d.lifecycleState} • Last seen: ${d.lastSeen ?? '-'}'),
                      trailing: TextButton(
                        onPressed: () => _claim(d),
                        child: const Text('Claim'),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
