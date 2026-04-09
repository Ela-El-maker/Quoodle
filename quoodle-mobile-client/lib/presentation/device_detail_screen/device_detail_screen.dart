import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge_widget.dart';
import './widgets/device_alerts_tab_widget.dart';
import './widgets/device_audit_tab_widget.dart';
import './widgets/device_commands_tab_widget.dart';
import './widgets/device_overview_tab_widget.dart';
import './widgets/device_telemetry_tab_widget.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Replace withRiverpod/Bloc for production
  late TabController _tabController;

  // Mock device data
  final Map<String, dynamic> _device = {
    'id': 'dev-007',
    'name': 'WKS-FINANCE-07',
    'status': 'degraded',
    'lastSeen': '12s ago',
    'riskScore': 71,
    'compliance': 'non_compliant',
    'os': 'Windows 10 Pro',
    'policySync': false,
    'agentVersion': '2.0.9',
    'ipAddress': '10.0.3.22',
    'hostname': 'WKSFINANCE07',
    'pairedAt': '2026-01-14T09:22:00Z',
    'assignedUser': 'L. Nakamura',
    'location': 'Tokyo HQ – Floor 3',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DeviceStatus get _deviceStatus {
    switch (_device['status'] as String) {
      case 'online':
        return DeviceStatus.online;
      case 'offline':
        return DeviceStatus.offline;
      case 'degraded':
        return DeviceStatus.degraded;
      case 'quarantined':
        return DeviceStatus.quarantined;
      default:
        return DeviceStatus.pending;
    }
  }

  Color get _statusBorderColor {
    switch (_deviceStatus) {
      case DeviceStatus.online:
        return AppTheme.statusOnline;
      case DeviceStatus.offline:
        return AppTheme.statusOffline;
      case DeviceStatus.degraded:
        return AppTheme.statusDegraded;
      case DeviceStatus.quarantined:
        return AppTheme.statusQuarantined;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      appBar: _buildGlassAppBar(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.sendCommandScreen),
        icon: const Icon(Icons.terminal_rounded, size: 18),
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
          // Device header
          _buildDeviceHeader(context, isTablet),
          // Tab bar
          _buildTabBar(),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                DeviceOverviewTabWidget(device: _device),
                DeviceTelemetryTabWidget(deviceId: _device['id'] as String),
                DeviceCommandsTabWidget(deviceId: _device['id'] as String),
                DeviceAlertsTabWidget(deviceId: _device['id'] as String),
                DeviceAuditTabWidget(deviceId: _device['id'] as String),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildGlassAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              border: const Border(
                bottom: BorderSide(color: AppTheme.borderLight, width: 1),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: AppTheme.textPrimary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        _device['name'] as String,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () => _showDeviceActions(context),
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

  Widget _buildDeviceHeader(BuildContext context, bool isTablet) {
    final riskScore = _device['riskScore'] as int;
    final riskColor = riskScore >= 80
        ? AppTheme.critical
        : riskScore >= 60
        ? AppTheme.error
        : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // OS icon container with status border
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _statusBorderColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _statusBorderColor.withAlpha(102),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _getOsIcon(_device['os'] as String),
                  size: 22,
                  color: _statusBorderColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusBadgeWidget.device(_deviceStatus),
                        const SizedBox(width: 8),
                        Text(
                          'Last seen ${_device['lastSeen']}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _device['hostname'] as String,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Risk score
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$riskScore',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: riskColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
          const SizedBox(height: 12),
          // Status chips row
          Row(
            children: [
              _HeaderChip(
                icon: Icons.verified_rounded,
                label: _device['compliance'] == 'compliant'
                    ? 'Compliant'
                    : 'Non-Compliant',
                color: _device['compliance'] == 'compliant'
                    ? AppTheme.secondary
                    : AppTheme.error,
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.sync_rounded,
                label: (_device['policySync'] as bool)
                    ? 'Policy Synced'
                    : 'Policy Drift',
                color: (_device['policySync'] as bool)
                    ? AppTheme.secondary
                    : AppTheme.warning,
              ),
              const SizedBox(width: 8),
              _HeaderChip(
                icon: Icons.router_rounded,
                label: _device['ipAddress'] as String,
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
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Telemetry'),
          Tab(text: 'Commands'),
          Tab(text: 'Alerts'),
          Tab(text: 'Audit'),
        ],
      ),
    );
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

  void _showDeviceActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
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
            const SizedBox(height: 20),
            Text(
              'Device Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _ActionTile(
              icon: Icons.terminal_rounded,
              label: 'Send Command',
              color: AppTheme.primary,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.sendCommandScreen);
              },
            ),
            _ActionTile(
              icon: Icons.notifications_outlined,
              label: 'View Alerts',
              color: AppTheme.warning,
              onTap: () {
                Navigator.pop(context);
                _tabController.animateTo(3);
              },
            ),
            _ActionTile(
              icon: Icons.lock_outlined,
              label: 'Lock Screen',
              color: AppTheme.textSecondary,
              onTap: () => Navigator.pop(context),
            ),
            _ActionTile(
              icon: Icons.block_rounded,
              label: 'Quarantine Device',
              color: AppTheme.error,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
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
          const SizedBox(width: 5),
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
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppTheme.textPrimary),
            ),
            const Spacer(),
            const Icon(
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
