import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import './widgets/alert_card_widget.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // TODO: Replace with Riverpod/Bloc for production
  bool _isLoading = true;
  int _selectedFilter = 0;
  int _currentNavIndex = 3;

  final List<String> _filters = ['All', 'Critical', 'High', 'Warning', 'Info'];

  static final List<Map<String, dynamic>> _alertMaps = [
    {
      'id': 'alert-041',
      'severity': 'critical',
      'deviceId': 'dev-021',
      'deviceName': 'EDGE-NODE-021',
      'message':
          'Attestation failure — device identity could not be verified. Quarantine enforced.',
      'timestamp': '10:58 AM',
      'acknowledged': false,
      'category': 'security',
    },
    {
      'id': 'alert-039',
      'severity': 'high',
      'deviceId': 'dev-014',
      'deviceName': 'PROD-SRV-014',
      'message':
          'Device offline — no heartbeat received for 18 minutes. Last command: collect_telemetry (failed).',
      'timestamp': '10:44 AM',
      'acknowledged': false,
      'category': 'availability',
    },
    {
      'id': 'alert-037',
      'severity': 'high',
      'deviceId': 'dev-007',
      'deviceName': 'WKS-FINANCE-07',
      'message':
          'Policy drift detected — reported hash abc3f9 does not match expected 7f3a9e.',
      'timestamp': '10:38 AM',
      'acknowledged': false,
      'category': 'compliance',
    },
    {
      'id': 'alert-035',
      'severity': 'warning',
      'deviceId': 'dev-007',
      'deviceName': 'WKS-FINANCE-07',
      'message':
          'Agent version 2.0.9 is below minimum recommended version (2.1.x). Upgrade required.',
      'timestamp': '09:12 AM',
      'acknowledged': false,
      'category': 'maintenance',
    },
    {
      'id': 'alert-033',
      'severity': 'warning',
      'deviceId': 'dev-019',
      'deviceName': 'EDGE-NODE-019',
      'message':
          'Disk usage at 84% — approaching threshold. Review and clean up if needed.',
      'timestamp': '08:45 AM',
      'acknowledged': true,
      'category': 'performance',
    },
    {
      'id': 'alert-031',
      'severity': 'info',
      'deviceId': 'dev-001',
      'deviceName': 'PROD-SRV-001',
      'message':
          'Scheduled compliance scan completed — all 14 rules passed. No action required.',
      'timestamp': '08:00 AM',
      'acknowledged': true,
      'category': 'compliance',
    },
    {
      'id': 'alert-028',
      'severity': 'info',
      'deviceId': 'dev-015',
      'deviceName': 'PROD-SRV-015',
      'message':
          'Agent updated to version 2.1.4 successfully. Policy re-applied.',
      'timestamp': '07:30 AM',
      'acknowledged': true,
      'category': 'maintenance',
    },
  ];

  List<Map<String, dynamic>> get _filteredAlerts {
    if (_selectedFilter == 0) return _alertMaps;
    final filterMap = {1: 'critical', 2: 'high', 3: 'warning', 4: 'info'};
    return _alertMaps
        .where((a) => a['severity'] == filterMap[_selectedFilter])
        .toList();
  }

  int get _unackedCount =>
      _alertMaps.where((a) => !(a['acknowledged'] as bool)).length;

  @override
  void initState() {
    super.initState();
    Future.delayed(
      const Duration(milliseconds: 600),
      () => mounted ? setState(() => _isLoading = false) : null,
    );
  }

  void _acknowledgeAlert(String alertId) {
    // TODO: Replace with real POST /api/alerts/{id}/ack for production
    final index = _alertMaps.indexWhere((a) => a['id'] == alertId);
    if (index >= 0) {
      setState(() {
        _alertMaps[index] = {..._alertMaps[index], 'acknowledged': true};
      });
    }
  }

  void _acknowledgeAll() {
    setState(() {
      for (int i = 0; i < _alertMaps.length; i++) {
        _alertMaps[i] = {..._alertMaps[i], 'acknowledged': true};
      }
    });
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
    final filtered = _filteredAlerts;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBody: true,
      appBar: GlassAppBar(
        title: 'Alerts',
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_rounded, size: 20),
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.notificationCenterScreen,
            ),
            tooltip: 'Notification Center',
          ),
          IconButton(
            icon: const Icon(Icons.schedule_rounded, size: 20),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.schedulerScreen),
            tooltip: 'Scheduler',
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.auditLogScreen),
            tooltip: 'Audit Log',
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, size: 20),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.analyticsScreen),
            tooltip: 'Analytics',
          ),
          if (_unackedCount > 0)
            TextButton(
              onPressed: _acknowledgeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                'Ack All',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _unackedCount > 0
                  ? AppTheme.errorMuted
                  : AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _unackedCount > 0
                    ? AppTheme.error.withAlpha(102)
                    : AppTheme.primary.withAlpha(77),
                width: 1,
              ),
            ),
            child: Text(
              '$_unackedCount UNACKED',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _unackedCount > 0 ? AppTheme.error : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersRow(),
          Expanded(
            child: _isLoading
                ? _buildSkeleton()
                : filtered.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Fleet is quiet',
                    subtitle:
                        'No alerts match the current filter. Your fleet is operating normally.',
                  )
                : isTablet
                ? _buildTabletGrid(filtered)
                : _buildPhoneList(filtered),
          ),
        ],
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          itemBuilder: (_, i) {
            final isSelected = i == _selectedFilter;
            final counts = [
              _alertMaps.length,
              _alertMaps.where((a) => a['severity'] == 'critical').length,
              _alertMaps.where((a) => a['severity'] == 'high').length,
              _alertMaps.where((a) => a['severity'] == 'warning').length,
              _alertMaps.where((a) => a['severity'] == 'info').length,
            ];
            final filterColors = [
              AppTheme.primary,
              AppTheme.critical,
              AppTheme.error,
              AppTheme.warning,
              AppTheme.primary,
            ];
            final color = filterColors[i];
            return GestureDetector(
              onTap: () => setState(() => _selectedFilter = i),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withAlpha(38)
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? color.withAlpha(128) : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _filters[i],
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected ? color : AppTheme.textSecondary,
                      ),
                    ),
                    if (counts[i] > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(51),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${counts[i]}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhoneList(List<Map<String, dynamic>> alerts) {
    return RefreshIndicator(
      onRefresh: () async =>
          await Future.delayed(const Duration(milliseconds: 800)),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        itemCount: alerts.length,
        itemBuilder: (ctx, i) {
          return FutureBuilder(
            future: Future.delayed(
              Duration(milliseconds: (i * 50).clamp(0, 300)),
            ),
            builder: (_, snap) {
              final ready = snap.connectionState == ConnectionState.done;
              return AnimatedOpacity(
                opacity: ready ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: AlertCardWidget(
                  alert: alerts[i],
                  onAcknowledge: (alerts[i]['acknowledged'] as bool)
                      ? null
                      : () => _acknowledgeAlert(alerts[i]['id'] as String),
                  onViewDevice: () =>
                      Navigator.pushNamed(ctx, AppRoutes.deviceDetailScreen),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabletGrid(List<Map<String, dynamic>> alerts) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: alerts.length,
      itemBuilder: (ctx, i) => AlertCardWidget(
        alert: alerts[i],
        onAcknowledge: (alerts[i]['acknowledged'] as bool)
            ? null
            : () => _acknowledgeAlert(alerts[i]['id'] as String),
        onViewDevice: () =>
            Navigator.pushNamed(ctx, AppRoutes.deviceDetailScreen),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: 5,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
