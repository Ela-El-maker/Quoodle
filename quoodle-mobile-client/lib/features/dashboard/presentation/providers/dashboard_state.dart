import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';

enum DashboardStatus { initial, loading, loaded, empty, error }

class DashboardState {
  const DashboardState({
    required this.status,
    this.summary,
    this.errorMessage,
    this.isRefreshing = false,
  });

  factory DashboardState.initial() =>
      const DashboardState(status: DashboardStatus.initial);

  final DashboardStatus status;
  final DashboardSummary? summary;
  final String? errorMessage;
  final bool isRefreshing;

  bool get isLoading =>
      status == DashboardStatus.loading || status == DashboardStatus.initial;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardSummary? summary,
    String? errorMessage,
    bool? isRefreshing,
    bool clearError = false,
  }) {
    return DashboardState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}
