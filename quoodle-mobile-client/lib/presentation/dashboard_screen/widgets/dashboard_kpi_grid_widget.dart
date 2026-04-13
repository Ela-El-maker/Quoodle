import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import '../../../theme/app_theme.dart';

class DashboardKpiGridWidget extends ConsumerWidget {
  const DashboardKpiGridWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      dashboardControllerProvider.select((state) => state.summary),
    );
    final totalDevices = summary?.totalDevices ?? 0;
    final onlineDevices = summary?.onlineDevices ?? 0;
    final offlineDevices = summary?.offlineDevices ?? 0;
    final activeCommands = summary?.activeCommands ?? 0;
    final criticalAlerts = summary?.criticalAlerts ?? 0;
    final complianceRate = summary?.complianceRate ?? 0;
    final compliantDevices = summary?.compliantDevices ?? 0;
    final policySyncRate = summary?.policySyncRate ?? 0;
    final syncedPolicyDevices = summary?.syncedPolicyDevices ?? 0;

    final kpis = [
      _KpiData(
        label: 'Online',
        value: '$onlineDevices',
        subtext: 'of $totalDevices devices',
        color: AppTheme.statusOnline,
        trend: null,
        trendUp: true,
      ),
      _KpiData(
        label: 'Offline',
        value: '$offlineDevices',
        subtext: 'need attention',
        color: AppTheme.statusQuarantined,
        trend: null,
        trendUp: false,
      ),
      _KpiData(
        label: 'Active Cmds',
        value: '$activeCommands',
        subtext: 'in progress',
        color: AppTheme.warning,
        trend: null,
        trendUp: true,
      ),
      _KpiData(
        label: 'Alerts',
        value: '$criticalAlerts',
        subtext: 'unacknowledged',
        color: AppTheme.critical,
        trend: null,
        trendUp: false,
      ),
      _KpiData(
        label: 'Compliance',
        value: '${complianceRate.round()}%',
        subtext: '$compliantDevices/$totalDevices compliant',
        color: AppTheme.secondary,
        trend: null,
        trendUp: false,
      ),
      _KpiData(
        label: 'Policy Sync',
        value: '${policySyncRate.round()}%',
        subtext: '$syncedPolicyDevices/$totalDevices synced',
        color: AppTheme.primary,
        trend: null,
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
