import 'package:flutter/material.dart';

import '../../models/telemetry.dart';
import '../../services/api_service.dart';

class TelemetryViewScreen extends StatefulWidget {
  const TelemetryViewScreen({super.key, required this.deviceId});

  final String deviceId;
  static const route = '/telemetry';

  @override
  State<TelemetryViewScreen> createState() => _TelemetryViewScreenState();
}

class _TelemetryViewScreenState extends State<TelemetryViewScreen> {
  final ApiService _api = ApiService();
  late Future<List<TelemetryPoint>> _history;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 4)).toIso8601String();
    final to = now.toIso8601String();
    _history = _api.fetchTelemetryHistory(widget.deviceId, from: from, to: to);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telemetry History')),
      body: FutureBuilder<List<TelemetryPoint>>(
        future: _history,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = snapshot.data!;
          return ListView.builder(
            itemCount: points.length,
            itemBuilder: (_, idx) {
              final p = points[idx];
              return ListTile(
                title: Text(p.timestamp ?? '-'),
                subtitle: Text('CPU ${p.avgCpu} RAM ${p.avgRam} Disk ${p.avgDiskUsage} Risk ${p.riskScoreAvg}'),
              );
            },
          );
        },
      ),
    );
  }
}
