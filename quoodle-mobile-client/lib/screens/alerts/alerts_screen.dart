import 'package:flutter/material.dart';

import '../../models/alert.dart';
import '../../services/api_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.deviceId});

  final String deviceId;
  static const route = '/alerts';

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final ApiService _api = ApiService();
  late Future<List<AlertItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchAlerts();
  }

  Future<void> _ack(String id) async {
    await _api.acknowledgeAlert(id);
    setState(() {
      _future = _api.fetchAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: FutureBuilder<List<AlertItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final alerts = snapshot.data!;
          return ListView.builder(
            itemCount: alerts.length,
            itemBuilder: (_, idx) {
              final alert = alerts[idx];
              return ListTile(
                leading: Icon(
                  Icons.warning_amber,
                  color: alert.severity == 'critical' ? Colors.red : Colors.orange,
                ),
                title: Text(alert.message ?? ''),
                subtitle: Text('${alert.category ?? ''} • ${alert.timestamp ?? ''}'),
                trailing: alert.acknowledged
                    ? const Icon(Icons.check, color: Colors.green)
                    : IconButton(
                        icon: const Icon(Icons.done),
                        onPressed: () => _ack(alert.alertId ?? ''),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
