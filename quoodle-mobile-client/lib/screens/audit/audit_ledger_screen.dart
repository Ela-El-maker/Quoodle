import 'package:flutter/material.dart';

import '../../models/audit_entry.dart';
import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/audit_entry_tile.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/offline_banner.dart';
import '../alerts/alerts_inbox_screen.dart';
import '../compliance/compliance_dashboard_screen.dart';

class AuditLedgerScreen extends StatefulWidget {
  const AuditLedgerScreen({super.key});

  @override
  State<AuditLedgerScreen> createState() => _AuditLedgerScreenState();
}

class _AuditLedgerScreenState extends State<AuditLedgerScreen> {
  final ApiService _api = ApiService();
  late Future<List<Device>> _devices;
  Future<List<AuditEntry>>? _entries;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _devices = _api.fetchDevices();
  }

  void _selectDevice(String deviceId) {
    setState(() {
      _deviceId = deviceId;
      _entries = _api.fetchAuditChain(deviceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activity'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Alerts'),
              Tab(text: 'Ledger'),
              Tab(text: 'Compliance'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const AlertsInboxScreen(embedded: true),
            Container(
              decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
              child: FutureBuilder<List<Device>>(
                future: _devices,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final devices = snapshot.data!;
                  if (devices.isEmpty) {
                    return const Center(child: Text('No devices available'));
                  }
                  _deviceId ??= devices.first.deviceId;
                  _entries ??= _api.fetchAuditChain(_deviceId!);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    children: [
                      const OfflineBanner(),
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ledger',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(
                              'Every command and policy decision is recorded here in a tamper-evident timeline.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButton<String>(
                                value: _deviceId,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                dropdownColor: AppColors.surface,
                                items: devices
                                    .map((device) => DropdownMenuItem(
                                          value: device.deviceId,
                                          child: Text(device.deviceName ??
                                              device.deviceId),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) _selectDevice(value);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<List<AuditEntry>>(
                        future: _entries,
                        builder: (context, entriesSnapshot) {
                          if (!entriesSnapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final entries = entriesSnapshot.data!;
                          if (entries.isEmpty) {
                            return Text(
                              'No audit entries for this device.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textMuted),
                            );
                          }
                          return Column(
                            children: entries
                                .map((entry) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: AuditEntryTile(entry: entry),
                                    ))
                                .toList(),
                          );
                        },
                      )
                    ],
                  );
                },
              ),
            ),
            const ComplianceDashboardScreen(),
          ],
        ),
      ),
    );
  }
}
