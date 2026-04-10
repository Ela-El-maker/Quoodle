class DashboardSummary {
  const DashboardSummary({
    required this.greeting,
    required this.operatorName,
    required this.lastUpdated,
    required this.itemsNeedingAttention,
  });

  final String greeting;
  final String operatorName;
  final String lastUpdated;
  final int itemsNeedingAttention;
}
