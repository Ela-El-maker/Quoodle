import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:secure_device_control/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:secure_device_control/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:secure_device_control/features/dashboard/domain/usecases/get_dashboard_summary.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_controller.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_state.dart';

final dashboardRemoteDataSourceProvider =
    Provider<DashboardRemoteDataSource>((ref) {
  return DashboardRemoteDataSource();
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(ref.read(dashboardRemoteDataSourceProvider));
});

final getDashboardSummaryProvider = Provider<GetDashboardSummary>((ref) {
  return GetDashboardSummary(ref.read(dashboardRepositoryProvider));
});

final dashboardControllerProvider =
    AutoDisposeNotifierProvider<DashboardController, DashboardState>(
        DashboardController.new);
