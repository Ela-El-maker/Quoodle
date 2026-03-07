import 'package:flutter/material.dart';

import '../../models/alert.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';

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
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: FutureBuilder<List<AlertItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final alerts = snapshot.data!
                .where((alert) => alert.deviceId == widget.deviceId)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Device alerts',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Soft, readable notices connected to this device.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (alerts.isEmpty)
                  Text(
                    'No alerts for this device right now.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  )
                else
                  ...alerts.map(
                    (alert) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _severityColor(alert.severity),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    alert.message ?? '-',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                                '${alert.category ?? 'Notice'} • ${alert.timestamp ?? '-'}'),
                            if (!alert.acknowledged) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () => _ack(alert.alertId ?? ''),
                                child: const Text('Acknowledge'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _severityColor(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'critical':
        return AppColors.riskCritical;
      case 'high':
        return AppColors.riskHigh;
      case 'medium':
        return AppColors.riskMedium;
      default:
        return AppColors.accentBlue;
    }
  }
}
