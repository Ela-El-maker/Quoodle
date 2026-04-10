import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_state.dart';

class DashboardController extends AutoDisposeNotifier<DashboardState> {
  @override
  DashboardState build() {
    Future<void>.microtask(load);
    return DashboardState.initial();
  }

  Future<void> load() async {
    state = state.copyWith(
      status: DashboardStatus.loading,
      isRefreshing: false,
      clearError: true,
    );

    final result = await ref.read(getDashboardSummaryProvider).call();

    state = result.when(
      success: (summary) => DashboardState(
        status: DashboardStatus.loaded,
        summary: summary,
      ),
      failure: (failure) => DashboardState(
        status: DashboardStatus.error,
        errorMessage: failure.userMessage,
      ),
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    final result = await ref.read(getDashboardSummaryProvider).call();

    state = result.when(
      success: (summary) => DashboardState(
        status: DashboardStatus.loaded,
        summary: summary,
        isRefreshing: false,
      ),
      failure: (failure) => DashboardState(
        status: DashboardStatus.error,
        errorMessage: failure.userMessage,
      ),
    );
  }
}
