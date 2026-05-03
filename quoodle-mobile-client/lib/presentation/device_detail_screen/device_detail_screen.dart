import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';

import '../../theme/app_theme.dart';
import '../../widgets/status_badge_widget.dart';
import './widgets/device_alerts_tab_widget.dart';
import './widgets/device_audit_tab_widget.dart';
import './widgets/device_commands_tab_widget.dart';
import './widgets/device_overview_tab_widget.dart';
import './widgets/device_telemetry_tab_widget.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key});

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _deviceId;

  void _handleBack() {
    AppNavigator.popOrGo(context, AppRoute.devices);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deviceId ??= _extractDeviceId(ModalRoute.of(context)?.settings.arguments);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDeviceId = _deviceId;
    if (selectedDeviceId == null || selectedDeviceId.trim().isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: Text('Device Detail'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _handleBack,
            ),
          ),
          body: Center(
            child: Text(
              'Device ID is missing. Open device from the fleet list.',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final deviceAsync = ref.watch(deviceDetailAsyncProvider(selectedDeviceId));

    final device = deviceAsync.when(
      data: (value) => value,
      loading: () => null,
      error: (_, __) => null,
    );

    if (deviceAsync.isLoading) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: Text('Device Detail'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _handleBack,
            ),
          ),
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      );
    }

    if (device == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: Text('Device Detail'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _handleBack,
            ),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Device not found for ID: $selectedDeviceId',
                  style: GoogleFonts.ibmPlexSans(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref
                      .invalidate(deviceDetailAsyncProvider(selectedDeviceId)),
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        extendBodyBehindAppBar: true,
        appBar: _buildGlassAppBar(context, device),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => AppNavigator.push(
            context,
            AppRoute.sendCommand,
            arguments: <String, dynamic>{
              'deviceId': device.id,
              'deviceName': device.name,
            },
          ),
          icon: Icon(Icons.terminal_rounded, size: 18),
          label: Text(
            'Send Command',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Column(
          children: [
            _buildDeviceHeader(device),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  DeviceOverviewTabWidget(device: _toDeviceMap(device)),
                  DeviceTelemetryTabWidget(deviceId: device.id),
                  DeviceCommandsTabWidget(deviceId: device.id),
                  DeviceAlertsTabWidget(deviceId: device.id),
                  DeviceAuditTabWidget(deviceId: device.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractDeviceId(Object? arguments) {
    if (arguments is String && arguments.isNotEmpty) {
      return arguments;
    }

    if (arguments is Map) {
      final map = arguments.cast<Object?, Object?>();
      final fromDeviceId = map['deviceId'];
      if (fromDeviceId is String && fromDeviceId.isNotEmpty) {
        return fromDeviceId;
      }
      final fromDeviceIdSnake = map['device_id'];
      if (fromDeviceIdSnake is String && fromDeviceIdSnake.isNotEmpty) {
        return fromDeviceIdSnake;
      }
      final fromId = map['id'];
      if (fromId is String && fromId.isNotEmpty) {
        return fromId;
      }
    }

    return null;
  }

  PreferredSizeWidget _buildGlassAppBar(
    BuildContext context,
    DeviceEntity device,
  ) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 1),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: AppTheme.textPrimary,
                      ),
                      onPressed: _handleBack,
                    ),
                    Expanded(
                      child: Text(
                        device.name,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () => _showDeviceActions(context, device),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceHeader(DeviceEntity device) {
    final riskScore = device.riskScore;
    final riskColor = riskScore >= 80
        ? AppTheme.critical
        : riskScore >= 60
            ? AppTheme.error
            : AppTheme.warning;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Icon(
                  _getOsIcon(device.os),
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusBadgeWidget.device(_deviceStatus(device.status)),
                        SizedBox(width: 8),
                        Text(
                          'Last seen ${device.lastSeen}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      device.hostname,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$riskScore',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: riskColor,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'RISK',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              _HeaderChip(
                icon: Icons.verified_rounded,
                label: device.compliance == DeviceComplianceType.compliant
                    ? 'Compliant'
                    : 'Non-Compliant',
                color: device.compliance == DeviceComplianceType.compliant
                    ? AppTheme.secondary
                    : AppTheme.error,
              ),
              SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.sync_rounded,
                label: device.policySync ? 'Policy Synced' : 'Policy Drift',
                color:
                    device.policySync ? AppTheme.secondary : AppTheme.warning,
              ),
              SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.router_rounded,
                label: device.ipAddress,
                color: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.surface,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(text: 'Overview'),
          Tab(text: 'Telemetry'),
          Tab(text: 'Commands'),
          Tab(text: 'Alerts'),
          Tab(text: 'Audit'),
        ],
      ),
    );
  }

  DeviceStatus _deviceStatus(DeviceStatusType status) {
    switch (status) {
      case DeviceStatusType.online:
        return DeviceStatus.online;
      case DeviceStatusType.offline:
        return DeviceStatus.offline;
      case DeviceStatusType.degraded:
        return DeviceStatus.degraded;
      case DeviceStatusType.quarantined:
        return DeviceStatus.quarantined;
      case DeviceStatusType.pending:
        return DeviceStatus.pending;
    }
  }

  IconData _getOsIcon(String os) {
    if (os.toLowerCase().contains('windows')) return Icons.window_rounded;
    if (os.toLowerCase().contains('ubuntu') ||
        os.toLowerCase().contains('debian')) {
      return Icons.terminal_rounded;
    }
    if (os.toLowerCase().contains('macos')) return Icons.laptop_mac_rounded;
    return Icons.devices_rounded;
  }

  void _showDeviceActions(BuildContext context, DeviceEntity device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Device Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 16),
            _ActionTile(
              icon: Icons.terminal_rounded,
              label: 'Send Command',
              color: AppTheme.primary,
              onTap: () {
                Navigator.maybePop(context);
                AppNavigator.push(
                  context,
                  AppRoute.sendCommand,
                  arguments: <String, dynamic>{
                    'deviceId': device.id,
                    'deviceName': device.name,
                  },
                );
              },
            ),
            _ActionTile(
              icon: Icons.notifications_outlined,
              label: 'View Alerts',
              color: AppTheme.warning,
              onTap: () {
                Navigator.maybePop(context);
                _tabController.animateTo(3);
              },
            ),
            _ActionTile(
              icon: Icons.lock_outlined,
              label: 'Lock Screen',
              color: AppTheme.textSecondary,
              onTap: () => Navigator.maybePop(context),
            ),
            _ActionTile(
              icon: Icons.block_rounded,
              label: 'Quarantine Device',
              color: AppTheme.error,
              onTap: () => Navigator.maybePop(context),
            ),
          ],
        ),
      ),
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

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(64), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(31),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppTheme.textPrimary),
            ),
            Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
