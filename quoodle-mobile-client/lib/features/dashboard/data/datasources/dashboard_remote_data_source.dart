import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';

class DashboardRemoteDataSource {
  Future<DashboardSummary> fetchSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return DashboardSummary(
      greeting: greeting,
      operatorName: 'Operator',
      lastUpdated: 'just now',
      itemsNeedingAttention: 3,
    );
  }
}
