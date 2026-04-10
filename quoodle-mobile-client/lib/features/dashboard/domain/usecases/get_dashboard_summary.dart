import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:secure_device_control/features/dashboard/domain/repositories/dashboard_repository.dart';

class GetDashboardSummary {
  const GetDashboardSummary(this._repository);

  final DashboardRepository _repository;

  Future<Result<DashboardSummary>> call() => _repository.getDashboardSummary();
}
