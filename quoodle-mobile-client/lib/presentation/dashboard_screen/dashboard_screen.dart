
import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/loading_skeleton_widget.dart';
import './widgets/dashboard_activity_feed_widget.dart';
import './widgets/dashboard_at_risk_widget.dart';
import './widgets/dashboard_fleet_chart_widget.dart';
import './widgets/dashboard_kpi_grid_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // TODO: Replace with Riverpod/Bloc for production
  bool _isLoading = true;
  bool _isRefreshing = false;
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _isRefreshing = false);
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBody: true,
      appBar: GlassAppBar(
        title: 'Fleet Overview',
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primaryDim,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: AppTheme.primary,
            size: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.textSecondary,
                  size: 22,
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.critical,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.background,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.alertsScreen),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildPhoneLayout() {
    if (_isLoading) return _buildSkeleton();
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildGreetingRow()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: const SliverToBoxAdapter(child: DashboardKpiGridWidget()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: const SliverToBoxAdapter(
              child: DashboardFleetChartWidget(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: const SliverToBoxAdapter(child: DashboardAtRiskWidget()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: const SliverToBoxAdapter(
              child: DashboardActivityFeedWidget(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    if (_isLoading) return _buildSkeleton();
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  sliver: SliverToBoxAdapter(child: _buildGreetingRow()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                  sliver: const SliverToBoxAdapter(
                    child: DashboardFleetChartWidget(),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 100),
                  sliver: const SliverToBoxAdapter(
                    child: DashboardActivityFeedWidget(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 100),
            child: Column(
              children: const [
                DashboardKpiGridWidget(),
                SizedBox(height: 16),
                DashboardAtRiskWidget(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGreetingRow() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, Operator',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Last updated: just now  ·  3 items need attention',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.errorMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.error.withAlpha(102), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.error,
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                '3 ALERTS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          const SkeletonCard(),
          const SkeletonCard(),
          const SkeletonCard(),
          const SkeletonCard(),
        ],
      ),
    );
  }
}
