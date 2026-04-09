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
        icon: Icons.circle_rounded,
        color: AppTheme.statusOnline,
        trend: '+2',
        trendUp: true,
      ),
      _KpiData(
        label: 'Offline',
        value: '5',
        subtext: 'need attention',
        icon: Icons.circle_outlined,
        color: AppTheme.statusQuarantined,
        trend: '+1',
        trendUp: false,
      ),
      _KpiData(
        label: 'Active Cmds',
        value: '3',
        subtext: 'in progress',
        icon: Icons.terminal_rounded,
        color: AppTheme.warning,
        trend: null,
        trendUp: true,
      ),
      _KpiData(
        label: 'Alerts',
        value: '3',
        subtext: 'unacknowledged',
        icon: Icons.notifications_rounded,
        color: AppTheme.critical,
        trend: '+3',
        trendUp: false,
      ),
      _KpiData(
        label: 'Compliance',
        value: '87%',
        subtext: '21/24 compliant',
        icon: Icons.verified_rounded,
        color: AppTheme.secondary,
        trend: '-4%',
        trendUp: false,
      ),
      _KpiData(
        label: 'Policy Sync',
        value: '92%',
        subtext: '22/24 synced',
        icon: Icons.sync_rounded,
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
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
  final IconData icon;
  final Color color;
  final String? trend;
  final bool trendUp;

  const _KpiData({
    required this.label,
    required this.value,
    required this.subtext,
    required this.icon,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: data.color.withAlpha(51), width: 1),
        boxShadow: [
          BoxShadow(
            color: data.color.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: data.color.withAlpha(31),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, size: 14, color: data.color),
              ),
              if (data.trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: data.trendUp
                        ? AppTheme.secondary.withAlpha(26)
                        : AppTheme.error.withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    data.trend!,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 9,
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
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: data.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                data.label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
