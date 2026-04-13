import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:secure_device_control/features/dashboard/presentation/providers/dashboard_state.dart';

class DashboardController extends AutoDisposeNotifier<DashboardState> {
  Timer? _autoRefreshTimer;

  @override
  DashboardState build() {
    Future<void>.microtask(load);
    _autoRefreshTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refreshSilently());
    });
    ref.onDispose(() {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    });
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

  Future<void> _refreshSilently() async {
    if (state.status == DashboardStatus.loading) {
      return;
    }

    final result = await ref.read(getDashboardSummaryProvider).call();
    state = result.when(
      success: (summary) => DashboardState(
        status: DashboardStatus.loaded,
        summary: summary,
      ),
      failure: (_) => state,
    );
  }
}
