import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_controller.dart';

void main() {
  test('SettingsController updates notification prefs and sessions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(settingsControllerProvider.notifier);

    controller.setNotifCriticalAlerts(false);
    expect(container.read(settingsControllerProvider).notifCriticalAlerts,
        isFalse);

    final sessionCount =
        container.read(settingsControllerProvider).sessions.length;
    controller.revokeAllOtherSessions();
    final sessions = container.read(settingsControllerProvider).sessions;
    expect(sessions.length, lessThan(sessionCount));
    expect(sessions.every((s) => s.isCurrent), isTrue);
  });
}
