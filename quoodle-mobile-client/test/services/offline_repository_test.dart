import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/commands/data/services/offline_command_queue.dart';

void main() {
  group('QueuedCommandStatus', () {
    test('contains expected values', () {
      expect(
        QueuedCommandStatus.values,
        containsAll([
          QueuedCommandStatus.pending,
          QueuedCommandStatus.syncing,
          QueuedCommandStatus.success,
          QueuedCommandStatus.failed,
          QueuedCommandStatus.retrying,
        ]),
      );
    });
  });

  group('QueuedCommand', () {
    test('copyWith updates status and retry metadata', () {
      final queued = QueuedCommand(
        id: '1',
        deviceId: 'd1',
        deviceName: 'Device 1',
        method: 'policy_sync',
        params: const {'force': true},
        queuedAt: DateTime.utc(2026, 1, 1),
      );

      final updated = queued.copyWith(
        status: QueuedCommandStatus.retrying,
        retryCount: 2,
      );

      expect(updated.status, QueuedCommandStatus.retrying);
      expect(updated.retryCount, 2);
      expect(updated.id, queued.id);
    });
  });
}
