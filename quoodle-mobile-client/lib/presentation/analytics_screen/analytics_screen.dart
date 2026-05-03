import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/analytics/presentation/providers/analytics_controller.dart';
import 'package:secure_device_control/features/analytics/presentation/providers/analytics_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final int _currentNavIndex = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analyticsState = ref.watch(analyticsControllerProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;

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
          title: Text(
            'Analytics',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          backgroundColor: AppTheme.surfaceVariant,
          actions: [
            _TimeRangePicker(
              selected: analyticsState.timeRange,
              options: AnalyticsState.timeRanges,
              onChanged: (v) => ref
                  .read(analyticsControllerProvider.notifier)
                  .setTimeRange(v),
            ),
            SizedBox(width: 8),
          ],
        ),
        body: isTablet
            ? Row(
                children: [
                  AppNavigation(
                    currentIndex: _currentNavIndex,
                    onTap: (i) => AppNavigator.navigateToTab(
                      context,
                      i,
                      profileTabTarget: ProfileTabTarget.settings,
                    ),
                  ),
                  Expanded(child: _buildBody(analyticsState)),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _buildBody(analyticsState)),
                  AppNavigation(
                    currentIndex: _currentNavIndex,
                    onTap: (i) => AppNavigator.navigateToTab(
                      context,
                      i,
                      profileTabTarget: ProfileTabTarget.settings,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _handleBack() {
    AppNavigator.popOrGo(context, AppRoute.alerts);
  }

  Widget _buildBody(AnalyticsState analyticsState) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _CommandSuccessTab(timeRange: analyticsState.timeRange),
              _DeviceHealthTab(timeRange: analyticsState.timeRange),
              _ComplianceTab(timeRange: analyticsState.timeRange),
              _OperatorActivityTab(timeRange: analyticsState.timeRange),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.primaryDim,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withAlpha(102)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textMuted,
        padding: const EdgeInsets.all(4),
        tabs: [
          Tab(text: 'Commands'),
          Tab(text: 'Health'),
          Tab(text: 'Compliance'),
          Tab(text: 'Operators'),
        ],
      ),
    );
  }
}

// ─── Time Range Picker ────────────────────────────────────────────────────────

class _TimeRangePicker extends StatelessWidget {
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _TimeRangePicker({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt == selected;
          return GestureDetector(
            onTap: () => onChanged(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryDim : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                opt,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Color? accentColor;
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                if (accentColor != null) ...[
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? delta;
  final bool deltaPositive;
  final Color color;
  const _KpiTile({
    required this.label,
    required this.value,
    this.delta,
    this.deltaPositive = true,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (delta != null) ...[
            SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  deltaPositive
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 10,
                  color: deltaPositive ? AppTheme.secondary : AppTheme.error,
                ),
                SizedBox(width: 2),
                Text(
                  delta!,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 10,
                    color: deltaPositive ? AppTheme.secondary : AppTheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Tab 1: Command Success ───────────────────────────────────────────────────

class _CommandSuccessTab extends StatelessWidget {
  final String timeRange;
  const _CommandSuccessTab({required this.timeRange});

  List<FlSpot> get _successRateSpots => [
        FlSpot(0, 88),
        FlSpot(1, 91),
        FlSpot(2, 87),
        FlSpot(3, 94),
        FlSpot(4, 92),
        FlSpot(5, 96),
        FlSpot(6, 93),
      ];

  List<FlSpot> get _failureRateSpots => [
        FlSpot(0, 12),
        FlSpot(1, 9),
        FlSpot(2, 13),
        FlSpot(3, 6),
        FlSpot(4, 8),
        FlSpot(5, 4),
        FlSpot(6, 7),
      ];

  static final _commandTypes = [
    {'name': 'screenshot', 'success': 98, 'total': 142},
    {'name': 'get_process_list', 'success': 95, 'total': 218},
    {'name': 'collect_filesystem', 'success': 89, 'total': 176},
    {'name': 'get_network_info', 'success': 94, 'total': 134},
    {'name': 'upload_file', 'success': 91, 'total': 87},
    {'name': 'reboot_device', 'success': 82, 'total': 44},
    {'name': 'get_system_info', 'success': 97, 'total': 201},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // KPI row
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: 'Success Rate',
                value: '93.2%',
                delta: '+2.1%',
                color: AppTheme.secondary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Total Commands',
                value: '1,002',
                delta: '+18%',
                color: AppTheme.primary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Avg Latency',
                value: '1.4s',
                delta: '-0.3s',
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Success rate trend
        _SectionCard(
          title: 'Success Rate Trend',
          subtitle: 'Daily success vs failure rate (%)',
          accentColor: AppTheme.secondary,
          child: SizedBox(
            height: 160,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppTheme.borderLight, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}%',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          final i = v.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            days[i],
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _successRateSpots,
                      isCurved: true,
                      color: AppTheme.secondary,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.secondary.withAlpha(26),
                      ),
                    ),
                    LineChartBarData(
                      spots: _failureRateSpots,
                      isCurved: true,
                      color: AppTheme.error,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.error.withAlpha(15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Per-command breakdown
        _SectionCard(
          title: 'Success Rate by Command Type',
          subtitle: 'Sorted by volume',
          accentColor: AppTheme.primary,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: _commandTypes.map((cmd) {
                final rate = (cmd['success'] as int) / 100.0;
                final color = rate >= 0.95
                    ? AppTheme.secondary
                    : rate >= 0.88
                        ? AppTheme.warning
                        : AppTheme.error;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cmd['name'] as String,
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${cmd['success']}% · ${cmd['total']} runs',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rate,
                          backgroundColor: AppTheme.borderLight,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Tab 2: Device Health ─────────────────────────────────────────────────────

class _DeviceHealthTab extends StatelessWidget {
  final String timeRange;
  const _DeviceHealthTab({required this.timeRange});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: 'Online Devices',
                value: '38',
                delta: '+3',
                color: AppTheme.secondary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Degraded',
                value: '5',
                delta: '-2',
                color: AppTheme.warning,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Offline',
                value: '3',
                delta: '+1',
                deltaPositive: false,
                color: AppTheme.error,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Fleet status donut
        _SectionCard(
          title: 'Fleet Status Distribution',
          subtitle: 'Current device health breakdown',
          accentColor: AppTheme.secondary,
          child: SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 50,
                      sections: [
                        PieChartSectionData(
                          value: 38,
                          color: AppTheme.secondary,
                          title: '38',
                          titleStyle: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          radius: 40,
                        ),
                        PieChartSectionData(
                          value: 5,
                          color: AppTheme.warning,
                          title: '5',
                          titleStyle: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          radius: 40,
                        ),
                        PieChartSectionData(
                          value: 3,
                          color: AppTheme.error,
                          title: '3',
                          titleStyle: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          radius: 40,
                        ),
                        PieChartSectionData(
                          value: 2,
                          color: AppTheme.textMuted,
                          title: '2',
                          titleStyle: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          radius: 40,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendItem(
                        color: AppTheme.secondary,
                        label: 'Online',
                        value: '38',
                      ),
                      SizedBox(height: 8),
                      _LegendItem(
                        color: AppTheme.warning,
                        label: 'Degraded',
                        value: '5',
                      ),
                      SizedBox(height: 8),
                      _LegendItem(
                        color: AppTheme.error,
                        label: 'Offline',
                        value: '3',
                      ),
                      SizedBox(height: 8),
                      _LegendItem(
                        color: AppTheme.textMuted,
                        label: 'Quarantine',
                        value: '2',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Health trend
        _SectionCard(
          title: 'Online Device Trend',
          subtitle: 'Devices online per day',
          accentColor: AppTheme.primary,
          child: SizedBox(
            height: 150,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppTheme.borderLight, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          final i = v.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            days[i],
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [35, 37, 34, 38, 36, 40, 38].asMap().entries.map((
                    e,
                  ) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.toDouble(),
                          color: AppTheme.primary,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 48,
                            color: AppTheme.borderLight,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Avg uptime by group
        _SectionCard(
          title: 'Avg Uptime by Device Group',
          subtitle: 'Last 7 days',
          accentColor: AppTheme.warning,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                {
                  'group': 'EDGE-NODES',
                  'uptime': 99.1,
                  'color': AppTheme.secondary,
                },
                {
                  'group': 'PROD-SERVERS',
                  'uptime': 97.4,
                  'color': AppTheme.secondary,
                },
                {
                  'group': 'WKS-FINANCE',
                  'uptime': 94.8,
                  'color': AppTheme.warning,
                },
                {
                  'group': 'WKS-OPS',
                  'uptime': 91.2,
                  'color': AppTheme.warning,
                },
                {
                  'group': 'QUARANTINE',
                  'uptime': 42.0,
                  'color': AppTheme.error,
                },
              ].map((item) {
                final uptime = item['uptime'] as double;
                final color = item['color'] as Color;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['group'] as String,
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${uptime.toStringAsFixed(1)}%',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: uptime / 100,
                          backgroundColor: AppTheme.borderLight,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─── Tab 3: Compliance ────────────────────────────────────────────────────────

class _ComplianceTab extends StatelessWidget {
  final String timeRange;
  const _ComplianceTab({required this.timeRange});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: 'Compliant',
                value: '84%',
                delta: '+3%',
                color: AppTheme.secondary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Policy Drifts',
                value: '7',
                delta: '-4',
                color: AppTheme.warning,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Violations',
                value: '2',
                delta: '-1',
                color: AppTheme.error,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Compliance score gauge
        _SectionCard(
          title: 'Overall Compliance Score',
          subtitle: 'Fleet-wide policy adherence',
          accentColor: AppTheme.secondary,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _ComplianceGauge(score: 84),
          ),
        ),
        // Policy compliance by category
        _SectionCard(
          title: 'Compliance by Policy Category',
          subtitle: 'Current pass rate per policy type',
          accentColor: Color(0xFFAB7FF8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                {'policy': 'Agent Version', 'pass': 91, 'fail': 9},
                {'policy': 'Disk Encryption', 'pass': 96, 'fail': 4},
                {'policy': 'Firewall Rules', 'pass': 88, 'fail': 12},
                {'policy': 'Patch Level', 'pass': 79, 'fail': 21},
                {'policy': 'TPM Attestation', 'pass': 94, 'fail': 6},
                {'policy': 'Log Forwarding', 'pass': 85, 'fail': 15},
              ].map((item) {
                final pass = item['pass'] as int;
                final fail = item['fail'] as int;
                final passColor = pass >= 90
                    ? AppTheme.secondary
                    : pass >= 80
                        ? AppTheme.warning
                        : AppTheme.error;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['policy'] as String,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '$pass% pass',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: passColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '$fail% fail',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              color: AppTheme.error.withAlpha(153),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: [
                            Container(
                              height: 6,
                              color: AppTheme.error.withAlpha(51),
                            ),
                            FractionallySizedBox(
                              widthFactor: pass / 100,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: passColor,
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Drift trend
        _SectionCard(
          title: 'Policy Drift Events',
          subtitle: 'Detected drifts per day',
          accentColor: AppTheme.warning,
          child: SizedBox(
            height: 140,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppTheme.borderLight, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          final i = v.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            days[i],
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 15,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        FlSpot(0, 11),
                        FlSpot(1, 8),
                        FlSpot(2, 13),
                        FlSpot(3, 7),
                        FlSpot(4, 9),
                        FlSpot(5, 5),
                        FlSpot(6, 7),
                      ],
                      isCurved: true,
                      color: AppTheme.warning,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.warning.withAlpha(26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComplianceGauge extends StatelessWidget {
  final int score;
  const _ComplianceGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 90
        ? AppTheme.secondary
        : score >= 75
            ? AppTheme.warning
            : AppTheme.error;
    return SizedBox(
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(160, 160),
            painter: _GaugePainter(score: score, color: color),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 20),
              Text(
                '$score%',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                'Compliant',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int score;
  final Color color;
  _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    final bgPaint = Paint()
      ..color = AppTheme.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * (score / 100),
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Tab 4: Operator Activity ─────────────────────────────────────────────────

class _OperatorActivityTab extends StatelessWidget {
  final String timeRange;
  const _OperatorActivityTab({required this.timeRange});

  static final _operators = [
    {
      'name': 'operator@quoodle.io',
      'role': 'Operator',
      'commands': 312,
      'success': 94,
      'lastActive': '10:41 AM',
    },
    {
      'name': 'admin@quoodle.io',
      'role': 'Admin',
      'commands': 87,
      'success': 98,
      'lastActive': '10:38 AM',
    },
    {
      'name': 'viewer@quoodle.io',
      'role': 'Viewer',
      'commands': 12,
      'success': 100,
      'lastActive': '10:22 AM',
    },
    {
      'name': 'ops-bot@quoodle.io',
      'role': 'System',
      'commands': 591,
      'success': 91,
      'lastActive': '10:41 AM',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: 'Active Operators',
                value: '4',
                color: AppTheme.primary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Total Actions',
                value: '1,002',
                delta: '+18%',
                color: AppTheme.secondary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _KpiTile(
                label: 'Denied Actions',
                value: '3',
                delta: '-2',
                color: AppTheme.error,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Activity by operator bar chart
        _SectionCard(
          title: 'Commands by Operator',
          subtitle: 'Total commands issued this period',
          accentColor: AppTheme.primary,
          child: SizedBox(
            height: 170,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppTheme.borderLight, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const labels = ['Oper.', 'Admin', 'View.', 'Bot'];
                          final i = v.toInt();
                          if (i < 0 || i >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              labels[i],
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 9,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [312, 87, 12, 591].asMap().entries.map((e) {
                    final colors = [
                      AppTheme.primary,
                      Color(0xFFAB7FF8),
                      AppTheme.warning,
                      AppTheme.secondary,
                    ];
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.toDouble(),
                          color: colors[e.key],
                          width: 28,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 620,
                            color: AppTheme.borderLight,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Operator leaderboard
        _SectionCard(
          title: 'Operator Leaderboard',
          subtitle: 'Activity ranking with success rates',
          accentColor: Color(0xFFAB7FF8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: _operators.asMap().entries.map((entry) {
                final i = entry.key;
                final op = entry.value;
                final successRate = op['success'] as int;
                final successColor = successRate >= 95
                    ? AppTheme.secondary
                    : successRate >= 88
                        ? AppTheme.warning
                        : AppTheme.error;
                final rankColors = [
                  Color(0xFFFFD700),
                  Color(0xFFC0C0C0),
                  Color(0xFFCD7F32),
                  AppTheme.textMuted,
                ];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.glassLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: rankColors[i].withAlpha(26),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: rankColors[i].withAlpha(102),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: rankColors[i],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              op['name'] as String,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                _RoleBadge(role: op['role'] as String),
                                SizedBox(width: 6),
                                Text(
                                  'Last: ${op['lastActive']}',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${op['commands']}',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'cmds',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            '$successRate% ok',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10,
                              color: successColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Hourly activity heatmap
        _SectionCard(
          title: 'Activity Heatmap',
          subtitle: 'Commands per hour (last 24h)',
          accentColor: AppTheme.warning,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _ActivityHeatmap(),
          ),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  Color get _color {
    switch (role) {
      case 'Admin':
        return Color(0xFFAB7FF8);
      case 'Operator':
        return AppTheme.primary;
      case 'Viewer':
        return AppTheme.warning;
      default:
        return AppTheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _color.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withAlpha(77)),
      ),
      child: Text(
        role,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 9,
          color: _color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActivityHeatmap extends StatelessWidget {
  final List<int> _hourlyData = [
    2,
    1,
    0,
    0,
    1,
    3,
    8,
    22,
    45,
    67,
    82,
    74,
    91,
    88,
    76,
    63,
    55,
    48,
    37,
    29,
    18,
    12,
    7,
    4,
  ];

  @override
  Widget build(BuildContext context) {
    final maxVal = _hourlyData.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(24, (i) {
            final val = _hourlyData[i];
            final intensity = maxVal > 0 ? val / maxVal : 0.0;
            final color = Color.lerp(
              AppTheme.borderLight,
              AppTheme.primary,
              intensity,
            )!;
            return Expanded(
              child: Tooltip(
                message: '${i.toString().padLeft(2, '0')}:00 — $val cmds',
                child: Container(
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
        SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['00', '06', '12', '18', '23']
              .map(
                (h) => Text(
                  h,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
