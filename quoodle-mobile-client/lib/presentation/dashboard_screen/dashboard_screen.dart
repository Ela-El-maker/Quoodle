import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_state.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../widgets/deferred_loader_widget.dart';
import './widgets/dashboard_activity_feed_widget.dart';
import './widgets/dashboard_at_risk_widget.dart';
import './widgets/dashboard_fleet_chart_widget.dart';
import './widgets/dashboard_kpi_grid_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentNavIndex = 0;

  Future<void> _onRefresh() async {
    await ref.read(dashboardControllerProvider.notifier).refresh();
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
    final dashboardState = ref.watch(dashboardControllerProvider);
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
            onPressed: () => AppNavigator.push(context, AppRoute.alerts),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isTablet
          ? _buildTabletLayout(dashboardState)
          : _buildPhoneLayout(dashboardState),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildPhoneLayout(DashboardState state) {
    if (state.isLoading) return _buildSkeleton();
    if (state.status == DashboardStatus.error) {
      return Center(
        child: Text(
          state.errorMessage ?? 'Failed to load dashboard.',
          style: GoogleFonts.ibmPlexSans(color: AppTheme.error),
        ),
      );
    }
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
            sliver: SliverToBoxAdapter(
              child: DeferredLoader(
                delay: const Duration(milliseconds: 600),
                builder: () => const DashboardAtRiskWidget(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverToBoxAdapter(
              child: DeferredLoader(
                delay: const Duration(milliseconds: 800),
                builder: () => const DashboardActivityFeedWidget(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(DashboardState state) {
    if (state.isLoading) return _buildSkeleton();
    if (state.status == DashboardStatus.error) {
      return Center(
        child: Text(
          state.errorMessage ?? 'Failed to load dashboard.',
          style: GoogleFonts.ibmPlexSans(color: AppTheme.error),
        ),
      );
    }
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
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Last updated: just now  ·  3 items need attention',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.errorMuted,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: AppTheme.error.withAlpha(80), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '3 ALERTS',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
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
