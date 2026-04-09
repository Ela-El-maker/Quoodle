import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import './widgets/device_card_widget.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace with Riverpod/Bloc for production
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedFilter = 0;
  int _currentNavIndex = 1;
  final _searchController = TextEditingController();
  late AnimationController _listAnimController;

  final List<String> _filters = ['All', 'Online', 'Offline', 'Degraded'];

  // Mock device data — Map-first pattern
  static final List<Map<String, dynamic>> _deviceMaps = [
    {
      'id': 'dev-001',
      'name': 'PROD-SRV-001',
      'status': 'online',
      'lastSeen': '2s ago',
      'riskScore': 12,
      'compliance': 'compliant',
      'os': 'Ubuntu 22.04',
      'policySync': true,
      'agentVersion': '2.1.4',
      'ipAddress': '10.0.1.11',
    },
    {
      'id': 'dev-002',
      'name': 'WKS-DEVOPS-02',
      'status': 'online',
      'lastSeen': '8s ago',
      'riskScore': 24,
      'compliance': 'compliant',
      'os': 'Windows 11',
      'policySync': true,
      'agentVersion': '2.1.4',
      'ipAddress': '10.0.2.45',
    },
    {
      'id': 'dev-003',
      'name': 'WKS-HR-003',
      'status': 'online',
      'lastSeen': '3s ago',
      'riskScore': 18,
      'compliance': 'compliant',
      'os': 'Windows 11',
      'policySync': true,
      'agentVersion': '2.1.3',
      'ipAddress': '10.0.2.67',
    },
    {
      'id': 'dev-007',
      'name': 'WKS-FINANCE-07',
      'status': 'degraded',
      'lastSeen': '12s ago',
      'riskScore': 71,
      'compliance': 'non_compliant',
      'os': 'Windows 10',
      'policySync': false,
      'agentVersion': '2.0.9',
      'ipAddress': '10.0.3.22',
    },
    {
      'id': 'dev-011',
      'name': 'WKS-DEVOPS-11',
      'status': 'online',
      'lastSeen': '5s ago',
      'riskScore': 31,
      'compliance': 'compliant',
      'os': 'macOS 14.3',
      'policySync': true,
      'agentVersion': '2.1.4',
      'ipAddress': '10.0.2.89',
    },
    {
      'id': 'dev-014',
      'name': 'PROD-SRV-014',
      'status': 'offline',
      'lastSeen': '18 min ago',
      'riskScore': 94,
      'compliance': 'unknown',
      'os': 'Ubuntu 20.04',
      'policySync': false,
      'agentVersion': '2.0.7',
      'ipAddress': '10.0.1.14',
    },
    {
      'id': 'dev-015',
      'name': 'PROD-SRV-015',
      'status': 'online',
      'lastSeen': '1s ago',
      'riskScore': 9,
      'compliance': 'compliant',
      'os': 'Ubuntu 22.04',
      'policySync': true,
      'agentVersion': '2.1.4',
      'ipAddress': '10.0.1.15',
    },
    {
      'id': 'dev-019',
      'name': 'EDGE-NODE-019',
      'status': 'online',
      'lastSeen': '4s ago',
      'riskScore': 43,
      'compliance': 'compliant',
      'os': 'Debian 12',
      'policySync': true,
      'agentVersion': '2.1.2',
      'ipAddress': '172.16.0.19',
    },
    {
      'id': 'dev-021',
      'name': 'EDGE-NODE-021',
      'status': 'quarantined',
      'lastSeen': '7 min ago',
      'riskScore': 98,
      'compliance': 'non_compliant',
      'os': 'Debian 11',
      'policySync': false,
      'agentVersion': '2.0.5',
      'ipAddress': '172.16.0.21',
    },
    {
      'id': 'dev-022',
      'name': 'WKS-LEGAL-22',
      'status': 'online',
      'lastSeen': '6s ago',
      'riskScore': 27,
      'compliance': 'compliant',
      'os': 'Windows 11',
      'policySync': true,
      'agentVersion': '2.1.4',
      'ipAddress': '10.0.4.11',
    },
  ];

  List<Map<String, dynamic>> get _filteredDevices {
    var result = _deviceMaps;
    if (_searchQuery.isNotEmpty) {
      result = result
          .where(
            (d) =>
                (d['name'] as String).toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (d['id'] as String).toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }
    if (_selectedFilter != 0) {
      final filterMap = {1: 'online', 2: 'offline', 3: 'degraded'};
      result = result
          .where((d) => d['status'] == filterMap[_selectedFilter])
          .toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _isLoading = false);
        _listAnimController.forward();
      }
    });
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    final routes = [
      AppRoutes.dashboardScreen,
      AppRoutes.devicesScreen,
      AppRoutes.commandTimelineScreen,
      AppRoutes.alertsScreen,
      AppRoutes.authenticationScreen,
    ];
    if (index != _currentNavIndex) {
      setState(() => _currentNavIndex = index);
      Navigator.pushNamedAndRemoveUntil(context, routes[index], (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final devices = _filteredDevices;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBody: true,
      appBar: GlassAppBar(
        title: 'Devices',
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primary.withAlpha(77),
                width: 1,
              ),
            ),
            child: Text(
              '${_deviceMaps.length} DEVICES',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.qrScannerScreen),
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
        label: Text(
          'Pair Device',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _isLoading
                ? _buildSkeleton()
                : devices.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.devices_other_rounded,
                    title: 'No devices found',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'No devices match "$_searchQuery". Try a different search.'
                        : 'No devices match the selected filter.',
                    actionLabel: _searchQuery.isEmpty ? 'Pair a Device' : null,
                    onAction: _searchQuery.isEmpty ? () {} : null,
                  )
                : isTablet
                ? _buildTabletGrid(devices)
                : _buildPhoneList(devices),
          ),
        ],
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search devices, IDs, IPs...',
                      hintStyle: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Filter chips
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (_, i) {
                final isSelected = i == _selectedFilter;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryDim
                          : AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary.withAlpha(128)
                            : AppTheme.border,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _filters[i],
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildPhoneList(List<Map<String, dynamic>> devices) {
    return RefreshIndicator(
      onRefresh: () async =>
          await Future.delayed(const Duration(milliseconds: 800)),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        itemCount: devices.length,
        itemBuilder: (ctx, i) {
          final delay = (i * 60).clamp(0, 400);
          return FutureBuilder(
            future: Future.delayed(Duration(milliseconds: delay)),
            builder: (_, snap) {
              final ready = snap.connectionState == ConnectionState.done;
              return AnimatedOpacity(
                opacity: ready ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                child: AnimatedSlide(
                  offset: ready ? Offset.zero : const Offset(0, 0.05),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: DeviceCardWidget(
                    device: devices[i],
                    onTap: () =>
                        Navigator.pushNamed(ctx, AppRoutes.deviceDetailScreen),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabletGrid(List<Map<String, dynamic>> devices) {
    return RefreshIndicator(
      onRefresh: () async =>
          await Future.delayed(const Duration(milliseconds: 800)),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
        ),
        itemCount: devices.length,
        itemBuilder: (ctx, i) => DeviceCardWidget(
          device: devices[i],
          onTap: () => Navigator.pushNamed(ctx, AppRoutes.deviceDetailScreen),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: 6,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
