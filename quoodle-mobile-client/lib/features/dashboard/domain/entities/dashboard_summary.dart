class DashboardSummary {
  const DashboardSummary({
    required this.greeting,
    required this.operatorName,
    required this.lastUpdated,
    required this.itemsNeedingAttention,
    required this.totalDevices,
    required this.onlineDevices,
    required this.offlineDevices,
    required this.activeCommands,
    required this.criticalAlerts,
    required this.complianceRate,
    required this.compliantDevices,
    required this.policySyncRate,
    required this.syncedPolicyDevices,
    required this.fleetHealthSeries,
    required this.atRiskDevices,
    required this.recentActivities,
  });

  final String greeting;
  final String operatorName;
  final String lastUpdated;
  final int itemsNeedingAttention;
  final int totalDevices;
  final int onlineDevices;
  final int offlineDevices;
  final int activeCommands;
  final int criticalAlerts;
  final double complianceRate;
  final int compliantDevices;
  final double policySyncRate;
  final int syncedPolicyDevices;
  final List<DashboardHealthPoint> fleetHealthSeries;
  final List<DashboardAtRiskDevice> atRiskDevices;
  final List<DashboardActivityItem> recentActivities;
}

class DashboardHealthPoint {
  const DashboardHealthPoint({
    required this.x,
    required this.y,
  });

  final double x;
  final double y;
}

class DashboardAtRiskDevice {
  const DashboardAtRiskDevice({
    required this.id,
    required this.name,
    required this.status,
    required this.reason,
    required this.riskScore,
  });

  final String id;
  final String name;
  final String status;
  final String reason;
  final int riskScore;
}

class DashboardActivityItem {
  const DashboardActivityItem({
    required this.commandMethod,
    required this.commandLabel,
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.timestampLabel,
    required this.initiator,
  });

  final String commandMethod;
  final String commandLabel;
  final String deviceId;
  final String deviceName;
  final String status;
  final String timestampLabel;
  final String initiator;
}
