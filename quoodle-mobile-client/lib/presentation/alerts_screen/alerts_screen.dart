import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_providers.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_state.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import './widgets/alert_card_widget.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  int _currentNavIndex = 3;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    Future<void>.microtask(
      () => ref.read(alertsControllerProvider.notifier).load(),
    );
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
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final state = ref.watch(alertsControllerProvider);
    final filtered = state.filteredAlerts;

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBody: true,
      appBar: GlassAppBar(
        title: 'Alerts',
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_rounded, size: 20),
            onPressed: () =>
                AppNavigator.push(context, AppRoute.notificationCenter),
            tooltip: 'Notification Center',
          ),
          IconButton(
            icon: const Icon(Icons.schedule_rounded, size: 20),
            onPressed: () => AppNavigator.push(context, AppRoute.scheduler),
            tooltip: 'Scheduler',
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            onPressed: () => AppNavigator.push(context, AppRoute.auditLog),
            tooltip: 'Audit Log',
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, size: 20),
            onPressed: () => AppNavigator.push(context, AppRoute.analytics),
            tooltip: 'Analytics',
          ),
          if (state.unackedCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(alertsControllerProvider.notifier).acknowledgeAll(),
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
              color: state.unackedCount > 0
                  ? AppTheme.errorMuted
                  : AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: state.unackedCount > 0
                    ? AppTheme.error.withAlpha(102)
                    : AppTheme.primary.withAlpha(77),
                width: 1,
              ),
            ),
            child: Text(
              '${state.unackedCount} UNACKED',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color:
                    state.unackedCount > 0 ? AppTheme.error : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersRow(state),
          Expanded(
            child: state.isLoading
                ? _buildSkeleton()
                : filtered.isEmpty
                    ? const EmptyStateWidget(
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

  Widget _buildFiltersRow(AlertsState state) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: AlertsFilter.values.length,
          itemBuilder: (_, i) {
            final filter = AlertsFilter.values[i];
            final isSelected = filter == state.selectedFilter;
            final count = _countForFilter(state, filter);
            final color = _filterColor(filter);
            return GestureDetector(
              onTap: () =>
                  ref.read(alertsControllerProvider.notifier).setFilter(filter),
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
                      filter.label,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? color : AppTheme.textSecondary,
                      ),
                    ),
                    if (count > 0) ...[
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
                          '$count',
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

  int _countForFilter(AlertsState state, AlertsFilter filter) {
    final severity = filter.severity;
    if (severity == null) {
      return state.alerts.length;
    }
    return state.alerts.where((alert) => alert.severity == severity).length;
  }

  Color _filterColor(AlertsFilter filter) {
    switch (filter) {
      case AlertsFilter.all:
        return AppTheme.primary;
      case AlertsFilter.critical:
        return AppTheme.critical;
      case AlertsFilter.high:
        return AppTheme.error;
      case AlertsFilter.warning:
        return AppTheme.warning;
      case AlertsFilter.info:
        return AppTheme.primary;
    }
  }

  Widget _buildPhoneList(List<AlertItem> alerts) {
    return RefreshIndicator(
      onRefresh: () => ref.read(alertsControllerProvider.notifier).refresh(),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        itemCount: alerts.length,
        itemBuilder: (ctx, i) {
          return FutureBuilder(
            future: Future<void>.delayed(
              Duration(milliseconds: (i * 50).clamp(0, 300)),
            ),
            builder: (_, snap) {
              final ready = snap.connectionState == ConnectionState.done;
              return AnimatedOpacity(
                opacity: ready ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: AlertCardWidget(
                  alert: _alertToMap(alerts[i]),
                  onAcknowledge: alerts[i].acknowledged
                      ? null
                      : () => ref
                          .read(alertsControllerProvider.notifier)
                          .acknowledgeAlert(alerts[i].id),
                  onViewDevice: () => AppNavigator.push(
                    ctx,
                    AppRoute.deviceDetail,
                    arguments: <String, dynamic>{
                      'deviceId': alerts[i].deviceId
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabletGrid(List<AlertItem> alerts) {
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
        alert: _alertToMap(alerts[i]),
        onAcknowledge: alerts[i].acknowledged
            ? null
            : () => ref
                .read(alertsControllerProvider.notifier)
                .acknowledgeAlert(alerts[i].id),
        onViewDevice: () => AppNavigator.push(
          ctx,
          AppRoute.deviceDetail,
          arguments: <String, dynamic>{'deviceId': alerts[i].deviceId},
        ),
      ),
    );
  }

  Map<String, dynamic> _alertToMap(AlertItem alert) {
    return <String, dynamic>{
      'id': alert.id,
      'severity': alert.severity.value,
      'deviceId': alert.deviceId,
      'deviceName': alert.deviceName,
      'message': alert.message,
      'timestamp': alert.timestamp,
      'acknowledged': alert.acknowledged,
      'category': alert.category,
    };
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: 5,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
