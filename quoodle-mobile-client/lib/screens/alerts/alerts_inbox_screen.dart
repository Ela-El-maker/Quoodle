import 'package:flutter/material.dart';

import '../../models/alert.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';

class AlertsInboxScreen extends StatefulWidget {
  const AlertsInboxScreen({super.key, this.embedded = false});

  static const route = '/alerts/inbox';
  final bool embedded;

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
    final content = Container(
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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                const OfflineBanner(),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Alerts',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Clear, readable notices from across the fleet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'No alerts right now. Your devices look stable.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...alerts.map((alert) => Padding(
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  if (alert.acknowledged)
                                    const Icon(Icons.check_circle_outline,
                                        color: AppColors.accentMint, size: 18),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${alert.category ?? 'Notice'} • ${alert.deviceId ?? 'Fleet'}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alert.timestamp ?? '-',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!alert.acknowledged) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton(
                                    onPressed: () => _ack(alert.alertId ?? ''),
                                    child: const Text('Acknowledge'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: content,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentBlue.withValues(alpha: 0.12)
              : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
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
