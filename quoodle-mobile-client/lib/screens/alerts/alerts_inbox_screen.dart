import 'package:flutter/material.dart';

import '../../models/alert.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';

class AlertsInboxScreen extends StatefulWidget {
  const AlertsInboxScreen({super.key});

  static const route = '/alerts/inbox';

  @override
  State<AlertsInboxScreen> createState() => _AlertsInboxScreenState();
}

class _AlertsInboxScreenState extends State<AlertsInboxScreen> {
  final ApiService _api = ApiService();
  late Future<List<AlertItem>> _future;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchAlerts();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _api.fetchAlerts(severity: _filter);
    });
    await _future;
  }

  Future<void> _ack(String id) async {
    await _api.acknowledgeAlert(id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts Inbox'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<AlertItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return ListView(
                  children: const [
                    SizedBox(
                        height: 320,
                        child: Center(child: CircularProgressIndicator()))
                  ],
                );
              }
              final alerts = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const OfflineBanner(),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alert filters',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _FilterChip(
                              label: 'All',
                              selected: _filter == null,
                              onTap: () => setState(() {
                                _filter = null;
                                _future = _api.fetchAlerts();
                              }),
                            ),
                            _FilterChip(
                              label: 'Critical',
                              selected: _filter == 'critical',
                              onTap: () => setState(() {
                                _filter = 'critical';
                                _future = _api.fetchAlerts(severity: 'critical');
                              }),
                            ),
                            _FilterChip(
                              label: 'High',
                              selected: _filter == 'high',
                              onTap: () => setState(() {
                                _filter = 'high';
                                _future = _api.fetchAlerts(severity: 'high');
                              }),
                            ),
                            _FilterChip(
                              label: 'Medium',
                              selected: _filter == 'medium',
                              onTap: () => setState(() {
                                _filter = 'medium';
                                _future = _api.fetchAlerts(severity: 'medium');
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (alerts.isEmpty)
                    Text(
                      'No alerts available.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    )
                  else
                    ...alerts.map((alert) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  color: _severityColor(alert.severity),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(alert.message ?? '-',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${alert.category ?? ''} • ${alert.timestamp ?? ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (alert.acknowledged)
                                  const Icon(Icons.check, color: AppColors.accentMint)
                                else
                                  IconButton(
                                    icon: const Icon(Icons.done),
                                    onPressed: () => _ack(alert.alertId ?? ''),
                                  ),
                              ],
                            ),
                          ),
                        )),
                ],
              );
            },
          ),
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
        return AppColors.textMuted;
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentBlue.withOpacity(0.25)
              : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accentBlue : AppColors.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
