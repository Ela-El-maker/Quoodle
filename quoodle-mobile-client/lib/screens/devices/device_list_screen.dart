import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/device_card.dart';
import '../../widgets/fleet_stats_header.dart';
import '../../widgets/offline_banner.dart';
import '../alerts/alerts_inbox_screen.dart';
import '../auth/login_screen.dart';
import '../pairing/qr_scan_screen.dart';
import '../system/system_status_screen.dart';
import 'device_detail_screen.dart';
import 'unpaired_devices_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  static const route = '/devices';

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final ApiService _api = ApiService();
  late Future<List<Device>> _devices;
  bool _filterOnline = false;
  bool _filterCompliant = false;
  bool _filterQuarantined = false;
  bool _filterAtRisk = false;
  String? _osFilter;

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

  List<Device> _applyFilters(List<Device> devices) {
    return devices.where((device) {
      if (_filterOnline && !_isOnline(device)) return false;
      if (_filterCompliant && !_isCompliant(device)) return false;
      if (_filterQuarantined && !_isQuarantined(device)) return false;
      if (_filterAtRisk && !_isAtRisk(device)) return false;
      if (_osFilter != null && !_matchesOs(device, _osFilter!)) return false;
      return true;
    }).toList();
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

  bool _matchesOs(Device device, String os) {
    final build = (device.osBuild ?? '').toLowerCase();
    return build.contains(os.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsInboxScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.monitor_heart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SystemStatusScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UnpairedDevicesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.pushNamed(context, QrScanScreen.route),
          ),
        ],
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
                    SessionStore.clear().then((_) {
                      if (mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          LoginScreen.route,
                          (_) => false,
                        );
                      }
                    });
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Failed to load devices'),
                        const SizedBox(height: 12),
                        Text(
                          error?.toString() ?? 'Unknown error',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
              final devices = snapshot.data!;
              if (devices.isEmpty) {
                return const Center(child: Text('No devices paired yet'));
              }
              final filtered = _applyFilters(devices);
              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 720 ? 2 : 1;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const OfflineBanner(),
                              Text(
                                'Secure fleet status',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              FleetStatsHeader(devices: devices),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilterChip(
                                label: const Text('Online'),
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
                                onSelected: (value) => setState(
                                    () => _filterQuarantined = value),
                              ),
                              FilterChip(
                                label: const Text('At risk'),
                                selected: _filterAtRisk,
                                onSelected: (value) =>
                                    setState(() => _filterAtRisk = value),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceRaised,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: DropdownButton<String>(
                                  value: _osFilter,
                                  hint: const Text('OS filter'),
                                  underline: const SizedBox.shrink(),
                                  dropdownColor: AppColors.surface,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Windows',
                                      child: Text('Windows'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Linux',
                                      child: Text('Linux'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'macOS',
                                      child: Text('macOS'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _osFilter = value),
                                ),
                              ),
                              if (_osFilter != null)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _osFilter = null),
                                  child: const Text('Clear OS'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final device = filtered[index];
                              return DeviceCard(
                                device: device,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DeviceDetailScreen(deviceId: device.deviceId),
                                  ),
                                ),
                              );
                            },
                            childCount: filtered.length,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: columns == 1 ? 1.35 : 1.1,
                          ),
                        ),
                      ),
                      if (filtered.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('No devices match filters')),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
