import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/analytics/presentation/providers/analytics_state.dart';

class AnalyticsController extends Notifier<AnalyticsState> {
  @override
  AnalyticsState build() {
    return AnalyticsState.initial();
  }

  void setTimeRange(String value) {
    state = state.copyWith(timeRange: value);
  }
}

final analyticsControllerProvider =
    NotifierProvider<AnalyticsController, AnalyticsState>(
  AnalyticsController.new,
);
