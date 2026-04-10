import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';

abstract class DashboardRepository {
  Future<Result<DashboardSummary>> getDashboardSummary();
}
