import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class DashboardKpiGridWidget extends StatelessWidget {
  const DashboardKpiGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _KpiData(
        label: 'Online',
        value: '19',
        subtext: 'of 24 devices',
        color: AppTheme.statusOnline,
        trend: '+2',
        trendUp: true,
      ),
      _KpiData(
        label: 'Offline',
        value: '5',
        subtext: 'need attention',
        color: AppTheme.statusQuarantined,
        trend: '+1',
        trendUp: false,
      ),
      _KpiData(
        label: 'Active Cmds',
        value: '3',
        subtext: 'in progress',
        color: AppTheme.warning,
        trend: null,
        trendUp: true,
      ),
      _KpiData(
        label: 'Alerts',
        value: '3',
        subtext: 'unacknowledged',
        color: AppTheme.critical,
        trend: '+3',
        trendUp: false,
      ),
      _KpiData(
        label: 'Compliance',
        value: '87%',
        subtext: '21/24 compliant',
        color: AppTheme.secondary,
        trend: '-4%',
        trendUp: false,
      ),
      _KpiData(
        label: 'Policy Sync',
        value: '92%',
        subtext: '22/24 synced',
        color: AppTheme.primary,
        trend: '+1%',
        trendUp: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fleet Metrics',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.3,
          ),
          itemCount: kpis.length,
          itemBuilder: (ctx, i) => _KpiCard(data: kpis[i]),
        ),
      ],
    );
  }
}

class _KpiData {
  final String label, value, subtext;
  final Color color;
  final String? trend;
  final bool trendUp;

  const _KpiData({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
    required this.trend,
    required this.trendUp,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                data.label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
              if (data.trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: data.trendUp
                        ? AppTheme.secondary.withAlpha(25)
                        : AppTheme.error.withAlpha(25),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    data.trend!,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: data.trendUp ? AppTheme.secondary : AppTheme.error,
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: data.color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtext,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
