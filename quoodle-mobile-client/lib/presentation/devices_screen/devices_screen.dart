import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_controller.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_state.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import './widgets/device_card_widget.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen>
    with SingleTickerProviderStateMixin {
  int _currentNavIndex = 1;
  final _searchController = TextEditingController();
  late AnimationController _listAnimController;

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _listAnimController.forward();
    Future<void>.microtask(() {
      ref.read(devicesControllerProvider.notifier).loadDevices();
    });
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index != _currentNavIndex) {
      setState(() => _currentNavIndex = index);
      AppNavigator.navigateToTab(
        context,
        index,
        profileTabTarget: ProfileTabTarget.settings,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(devicesControllerProvider.notifier);
    final state = ref.watch(devicesControllerProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final devices = state.filteredDevices;

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
              '${state.allDevices.length} DEVICES',
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
        onPressed: () => AppNavigator.push(context, AppRoute.qrScanner),
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
          _buildSearchAndFilters(state, controller),
          Expanded(
            child: state.isLoading
                ? _buildSkeleton()
                : devices.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.devices_other_rounded,
                        title: 'No devices found',
                        subtitle: state.errorMessage != null
                            ? state.errorMessage!
                            : state.searchQuery.isNotEmpty
                                ? 'No devices match "${state.searchQuery}". Try a different search.'
                                : 'No devices match the selected filter.',
                        actionLabel: state.errorMessage != null
                            ? 'Retry'
                            : (state.searchQuery.isEmpty
                                ? 'Pair a Device'
                                : null),
                        onAction: state.errorMessage != null
                            ? () => ref
                                .read(devicesControllerProvider.notifier)
                                .loadDevices()
                            : (state.searchQuery.isEmpty ? () {} : null),
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

  Widget _buildSearchAndFilters(
    DevicesState state,
    DevicesController controller,
  ) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8.0),
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
                    onChanged: controller.setSearchQuery,
                  ),
                ),
                if (state.searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      controller.clearSearch();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: DevicesFilter.values.length,
              itemBuilder: (_, i) {
                final filter = DevicesFilter.values[i];
                final isSelected = filter == state.selectedFilter;
                return GestureDetector(
                  onTap: () => controller.setFilter(filter),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? AppTheme.primaryDim : AppTheme.surface,
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary.withAlpha(100)
                            : AppTheme.border,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      filter.label,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPhoneList(List<DeviceEntity> devices) {
    return RefreshIndicator(
      onRefresh: () async =>
          await ref.read(devicesControllerProvider.notifier).loadDevices(),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        itemCount: devices.length,
        itemBuilder: (ctx, i) {
          final delay = (i * 60).clamp(0, 400);
          return FutureBuilder<void>(
            future: Future<void>.delayed(Duration(milliseconds: delay)),
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
                    device: _toDeviceMap(devices[i]),
                    onTap: () => AppNavigator.push(
                      ctx,
                      AppRoute.deviceDetail,
                      arguments: <String, dynamic>{'deviceId': devices[i].id},
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabletGrid(List<DeviceEntity> devices) {
    return RefreshIndicator(
      onRefresh: () async =>
          await ref.read(devicesControllerProvider.notifier).loadDevices(),
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
          device: _toDeviceMap(devices[i]),
          onTap: () => AppNavigator.push(
            ctx,
            AppRoute.deviceDetail,
            arguments: <String, dynamic>{'deviceId': devices[i].id},
          ),
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

  Map<String, dynamic> _toDeviceMap(DeviceEntity device) {
    return <String, dynamic>{
      'id': device.id,
      'name': device.name,
      'status': _statusToRaw(device.status),
      'lastSeen': device.lastSeen,
      'riskScore': device.riskScore,
      'compliance': _complianceToRaw(device.compliance),
      'os': device.os,
      'policySync': device.policySync,
      'agentVersion': device.agentVersion,
      'ipAddress': device.ipAddress,
      'hostname': device.hostname,
      'pairedAt': device.pairedAt,
      'assignedUser': device.assignedUser,
      'location': device.location,
    };
  }

  String _statusToRaw(DeviceStatusType status) {
    switch (status) {
      case DeviceStatusType.online:
        return 'online';
      case DeviceStatusType.offline:
        return 'offline';
      case DeviceStatusType.degraded:
        return 'degraded';
      case DeviceStatusType.quarantined:
        return 'quarantined';
      case DeviceStatusType.pending:
        return 'pending';
    }
  }

  String _complianceToRaw(DeviceComplianceType compliance) {
    switch (compliance) {
      case DeviceComplianceType.compliant:
        return 'compliant';
      case DeviceComplianceType.nonCompliant:
        return 'non_compliant';
      case DeviceComplianceType.unknown:
        return 'unknown';
    }
  }
}
