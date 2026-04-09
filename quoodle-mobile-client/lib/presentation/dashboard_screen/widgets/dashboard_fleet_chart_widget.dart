import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class DashboardFleetChartWidget extends StatefulWidget {
  const DashboardFleetChartWidget({super.key});

  @override
  State<DashboardFleetChartWidget> createState() =>
      _DashboardFleetChartWidgetState();
}

class _DashboardFleetChartWidgetState extends State<DashboardFleetChartWidget> {
  int _selectedWindow = 0; // 0=24h, 1=7d, 2=30d
  final List<String> _windows = ['24h', '7d', '30d'];

  // Fleet health % over last 24 hours (hourly)
  final List<FlSpot> _healthData = [
    const FlSpot(0, 95),
    const FlSpot(1, 95),
    const FlSpot(2, 94),
    const FlSpot(3, 91),
    const FlSpot(4, 88),
    const FlSpot(5, 88),
    const FlSpot(6, 87),
    const FlSpot(7, 83),
    const FlSpot(8, 79),
    const FlSpot(9, 79),
    const FlSpot(10, 82),
    const FlSpot(11, 85),
    const FlSpot(12, 86),
    const FlSpot(13, 88),
    const FlSpot(14, 90),
    const FlSpot(15, 88),
    const FlSpot(16, 85),
    const FlSpot(17, 84),
    const FlSpot(18, 87),
    const FlSpot(19, 89),
    const FlSpot(20, 91),
    const FlSpot(21, 90),
    const FlSpot(22, 88),
    const FlSpot(23, 79),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
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
              Row(
                children: List.generate(_windows.length, (i) {
                  final isSelected = i == _selectedWindow;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedWindow = i),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryDim
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary.withAlpha(102)
                              : AppTheme.border,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _windows[i],
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 11,
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
                    tooltipBgColor: AppTheme.surfaceElevated,
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
                    spots: _healthData,
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
                      checkToShowDot: (spot, _) => spot.y < 85 || spot.x == 23,
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
