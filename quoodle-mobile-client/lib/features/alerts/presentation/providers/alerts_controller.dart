import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_providers.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_state.dart';

class AlertsController extends AutoDisposeNotifier<AlertsState> {
  @override
  AlertsState build() {
    return AlertsState.initial();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    state = state.copyWith(
      isLoading: false,
      alerts: ref.read(getAlertsProvider).call(),
    );
  }

  Future<void> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    state = state.copyWith(alerts: ref.read(getAlertsProvider).call());
  }

  void setFilter(AlertsFilter filter) {
    state = state.copyWith(selectedFilter: filter);
  }

  void acknowledgeAlert(String alertId) {
    ref.read(acknowledgeAlertProvider).call(alertId);
    state = state.copyWith(alerts: ref.read(getAlertsProvider).call());
  }

  void acknowledgeAll() {
    ref.read(acknowledgeAllAlertsProvider).call();
    state = state.copyWith(alerts: ref.read(getAlertsProvider).call());
  }
}
