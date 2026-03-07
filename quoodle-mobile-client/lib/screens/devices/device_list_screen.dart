import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/device_card.dart';
import '../../widgets/fleet_stats_header.dart';
import '../../widgets/offline_banner.dart';
import '../auth/login_screen.dart';
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
  bool _redirectingToLogin = false;
  bool _filterOnline = false;
  bool _filterCompliant = false;
  bool _filterQuarantined = false;
  bool _filterAtRisk = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _devices = _api.fetchDevices();
  }

  Future<void> _refresh() async {
    setState(() {
      _devices = _api.fetchDevices();
    });
    await _devices;
  }

  Future<void> _handleUnauthorized() async {
    if (_redirectingToLogin) return;
    _redirectingToLogin = true;

    await SessionStore.clear();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      LoginScreen.route,
      (_) => false,
    );
  }

  List<Device> _applyFilters(List<Device> devices) {
    final filtered = devices.where((device) {
      if (_filterOnline && !_isOnline(device)) return false;
      if (_filterCompliant && !_isCompliant(device)) return false;
      if (_filterQuarantined && !_isQuarantined(device)) return false;
      if (_filterAtRisk && !_isAtRisk(device)) return false;
      if (_query.isNotEmpty) {
        final haystack =
            '${device.deviceName ?? ''} ${device.deviceId} ${device.osBuild ?? ''}'
                .toLowerCase();
        if (!haystack.contains(_query.trim().toLowerCase())) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final onlineCompare = _onlineRank(b).compareTo(_onlineRank(a));
      if (onlineCompare != 0) return onlineCompare;

      final seenCompare = _lastSeenValue(b).compareTo(_lastSeenValue(a));
      if (seenCompare != 0) return seenCompare;

      return (a.deviceName ?? a.deviceId)
          .toLowerCase()
          .compareTo((b.deviceName ?? b.deviceId).toLowerCase());
    });

    return filtered;
  }

  bool _isOnline(Device device) {
    final state = device.lifecycleState.toLowerCase();
    return state.contains('online') || state.contains('active');
  }

  bool _isCompliant(Device device) {
    final status = (device.complianceStatus ?? '').toLowerCase();
    return status.contains('compliant') || status.contains('ok');
  }

  bool _isQuarantined(Device device) {
    final status = (device.complianceStatus ?? '').toLowerCase();
    return status.contains('quarantine');
  }

  bool _isAtRisk(Device device) => (device.riskScore ?? 0) >= 60;

  int _onlineRank(Device device) => _isOnline(device) ? 1 : 0;

  int _lastSeenValue(Device device) {
    final seen = device.lastSeen;
    if (seen == null || seen.isEmpty) return 0;
    return DateTime.tryParse(seen)?.millisecondsSinceEpoch ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => Navigator.pushNamed(context, QrScanScreen.route),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, QrScanScreen.route),
        icon: const Icon(Icons.add),
        label: const Text('Pair'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Device>>(
            future: _devices,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  if (error is ApiException && error.statusCode == 401) {
                    _handleUnauthorized();
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    children: [
                      const SizedBox(height: 180),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Unable to load devices',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              Text(
                                error?.toString() ?? 'Unknown error',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                  onPressed: _refresh,
                                  child: const Text('Try again')),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
              final devices = snapshot.data!;
              final filtered = _applyFilters(devices);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                children: [
                  const OfflineBanner(),
                  Text(
                    'A clear view of every paired device.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  FleetStatsHeader(devices: devices),
                  const SizedBox(height: 20),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search by name, device ID, or platform',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Active'),
                        selected: _filterOnline,
                        onSelected: (value) =>
                            setState(() => _filterOnline = value),
                      ),
                      FilterChip(
                        label: const Text('Compliant'),
                        selected: _filterCompliant,
                        onSelected: (value) =>
                            setState(() => _filterCompliant = value),
                      ),
                      FilterChip(
                        label: const Text('Quarantined'),
                        selected: _filterQuarantined,
                        onSelected: (value) =>
                            setState(() => _filterQuarantined = value),
                      ),
                      FilterChip(
                        label: const Text('Needs attention'),
                        selected: _filterAtRisk,
                        onSelected: (value) =>
                            setState(() => _filterAtRisk = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (devices.isEmpty)
                    const _EmptyState(
                      title: 'No devices yet',
                      message:
                          'When you pair your first device, it will appear here.',
                    )
                  else if (filtered.isEmpty)
                    const _EmptyState(
                      title: 'No matching devices',
                      message: 'Try relaxing the filters or search terms.',
                    )
                  else
                    ...filtered.map(
                      (device) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DeviceCard(
                          device: device,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeviceDetailScreen(deviceId: device.deviceId),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
