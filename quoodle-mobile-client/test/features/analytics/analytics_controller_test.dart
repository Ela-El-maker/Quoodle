import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/analytics/presentation/providers/analytics_controller.dart';

void main() {
  test('AnalyticsController changes time range', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(analyticsControllerProvider.notifier);
    expect(container.read(analyticsControllerProvider).timeRange, '7d');

    controller.setTimeRange('30d');
    expect(container.read(analyticsControllerProvider).timeRange, '30d');
  });
}
