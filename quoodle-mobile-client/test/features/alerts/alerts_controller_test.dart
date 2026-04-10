import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';
import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_providers.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_state.dart';

class _FakeAlertsRepository implements AlertsRepository {
  _FakeAlertsRepository(this._alerts);

  List<AlertItem> _alerts;

  @override
  List<AlertItem> getAlerts() => List<AlertItem>.unmodifiable(_alerts);

  @override
  void acknowledgeAlert(String alertId) {
    _alerts = _alerts
        .map((a) => a.id == alertId ? a.copyWith(acknowledged: true) : a)
        .toList();
  }

  @override
  void acknowledgeAll() {
    _alerts = _alerts.map((a) => a.copyWith(acknowledged: true)).toList();
  }
}

void main() {
  test('AlertsController loads, filters, and acknowledges alerts', () async {
    final fakeRepository = _FakeAlertsRepository([
      const AlertItem(
        id: 'a1',
        severity: AlertSeverityType.critical,
        deviceId: 'dev-01',
        deviceName: 'NODE-01',
        message: 'critical',
        timestamp: '10:00',
        acknowledged: false,
        category: 'security',
      ),
      const AlertItem(
        id: 'a2',
        severity: AlertSeverityType.warning,
        deviceId: 'dev-02',
        deviceName: 'NODE-02',
        message: 'warning',
        timestamp: '10:01',
        acknowledged: true,
        category: 'maintenance',
      ),
    ]);

    final container = ProviderContainer(
      overrides: [alertsRepositoryProvider.overrideWithValue(fakeRepository)],
    );
    final sub = container.listen(
      alertsControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    await container.read(alertsControllerProvider.notifier).load();

    expect(container.read(alertsControllerProvider).alerts.length, 2);
    expect(container.read(alertsControllerProvider).unackedCount, 1);

    container
        .read(alertsControllerProvider.notifier)
        .setFilter(AlertsFilter.critical);
    expect(
      container.read(alertsControllerProvider).filteredAlerts.single.id,
      'a1',
    );

    container.read(alertsControllerProvider.notifier).acknowledgeAlert('a1');
    expect(container.read(alertsControllerProvider).unackedCount, 0);
  });
}
