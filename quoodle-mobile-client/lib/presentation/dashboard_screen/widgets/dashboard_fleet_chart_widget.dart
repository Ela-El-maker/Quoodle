import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import '../../../theme/app_theme.dart';

class DashboardFleetChartWidget extends ConsumerStatefulWidget {
  const DashboardFleetChartWidget({super.key});

  @override
  ConsumerState<DashboardFleetChartWidget> createState() =>
      _DashboardFleetChartWidgetState();
}

class _DashboardFleetChartWidgetState
    extends ConsumerState<DashboardFleetChartWidget> {
  int _selectedWindow = 0; // 0=24h, 1=7d, 2=30d
  final List<String> _windows = ['24h', '7d', '30d'];

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(
      dashboardControllerProvider.select((state) => state.summary),
    );
    final healthData = _buildHealthData(summary?.fleetHealthSeries ?? const []);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fleet Health',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Online device ratio over time',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: List.generate(_windows.length, (i) {
                      final isSelected = i == _selectedWindow;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedWindow = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryDim
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary.withAlpha(80)
                                  : AppTheme.border,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _windows[i],
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 60,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.border.withAlpha(128),
                    strokeWidth: 1,
                    dashArray: [4, 6],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      reservedSize: 36,
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
                      interval: 4,
                      reservedSize: 20,
                      getTitlesWidget: (v, _) {
                        final h = v.toInt();
                        if (h % 4 != 0) return const SizedBox.shrink();
                        return Text(
                          '${h}h',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surfaceElevated,
                    tooltipRoundedRadius: 8,
                    tooltipBorder: const BorderSide(
                      color: AppTheme.border,
                      width: 1,
                    ),
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            '${s.y.toInt()}% online',
                            GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: healthData,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppTheme.primary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) {
                        final isLow = spot.y < 85;
                        return FlDotCirclePainter(
                          radius: isLow ? 3.5 : 2,
                          color: isLow ? AppTheme.error : AppTheme.primary,
                          strokeWidth: 1.5,
                          strokeColor: AppTheme.background,
                        );
                      },
                      checkToShowDot: (spot, _) =>
                          spot.y < 85 || spot.x == healthData.last.x,
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withAlpha(51),
                          AppTheme.primary.withAlpha(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: AppTheme.primary, label: 'Fleet health %'),
              const SizedBox(width: 16),
              _LegendDot(color: AppTheme.error, label: 'Below threshold'),
            ],
          ),
        ],
      ),
    );
  }

  List<FlSpot> _buildHealthData(List<DashboardHealthPoint> points) {
    if (points.isEmpty) {
      return const <FlSpot>[
        FlSpot(0, 0),
        FlSpot(1, 0),
      ];
    }

    return points
        .map(
          (point) => FlSpot(
            point.x,
            point.y.clamp(0, 100),
          ),
        )
        .toList(growable: false);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}
