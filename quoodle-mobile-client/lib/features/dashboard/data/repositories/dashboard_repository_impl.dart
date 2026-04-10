import 'package:secure_device_control/core/errors/failure_mapper.dart';
import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:secure_device_control/features/dashboard/domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._remoteDataSource);

  final DashboardRemoteDataSource _remoteDataSource;

  @override
  Future<Result<DashboardSummary>> getDashboardSummary() async {
    try {
      final summary = await _remoteDataSource.fetchSummary();
      return Success<DashboardSummary>(summary);
    } on Object catch (error) {
      return FailureResult<DashboardSummary>(FailureMapper.fromObject(error));
    }
  }
}
