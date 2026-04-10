import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_providers.dart';

class _FakeCommandTimelineRepository implements CommandTimelineRepository {
  _FakeCommandTimelineRepository({List<CommandResult>? seeded}) {
    if (seeded != null) {
      for (final item in seeded) {
        _store[item.commandId] = item;
      }
    }
  }

  final Map<String, CommandResult> _store = {};
  final List<CommandResult> savedResults = [];

  @override
  Future<CommandResult?> loadResult(String commandId) async {
    return _store[commandId];
  }

  @override
  Future<void> saveResult(CommandResult result) async {
    _store[result.commandId] = result;
    savedResults.add(result);
  }
}

void main() {
  group('CommandTimelineController', () {
    test('polls to completion and persists result', () async {
      final fakeRepository = _FakeCommandTimelineRepository();

      final container = ProviderContainer(
        overrides: [
          commandTimelineRepositoryProvider.overrideWithValue(fakeRepository),
          commandTimelineTickIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          commandTimelinePollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          commandTimelinePollThresholdProvider.overrideWithValue(1),
        ],
      );
      final sub = container.listen(
        commandTimelineControllerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      addTearDown(container.dispose);

      await container
          .read(commandTimelineControllerProvider.notifier)
          .initialize(<String, dynamic>{
        'id': 'cmd-test-1',
        'method': 'policy_sync',
        'params': <String, dynamic>{'force': true},
      });

      await Future<void>.delayed(const Duration(milliseconds: 40));

      final state = container.read(commandTimelineControllerProvider);
      expect(state.status, CommandExecutionStatus.completed);
      expect(state.command['id'], 'cmd-test-1');
      expect(state.command['params'], contains('"force":true'));
      expect(fakeRepository.savedResults.length, 1);
      expect(fakeRepository.savedResults.single.commandId, 'cmd-test-1');
    });

    test('restores cached result and skips polling completion path', () async {
      final seeded = CommandResult(
        commandId: 'cmd-cached',
        method: 'lock_screen',
        deviceId: 'dev-007',
        deviceName: 'WKS-FINANCE-07',
        initiator: 'System',
        status: CommandExecutionStatus.failed,
        commandData: const <String, dynamic>{
          'id': 'cmd-cached',
          'method': 'lock_screen',
          'deviceId': 'dev-007',
          'deviceName': 'WKS-FINANCE-07',
          'initiator': 'System',
          'params': '{"reason": "operator_initiated"}',
        },
        savedAt: DateTime(2026, 4, 10),
      );
      final fakeRepository = _FakeCommandTimelineRepository(seeded: [seeded]);

      final container = ProviderContainer(
        overrides: [
          commandTimelineRepositoryProvider.overrideWithValue(fakeRepository),
          commandTimelineTickIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          commandTimelinePollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          commandTimelinePollThresholdProvider.overrideWithValue(1),
        ],
      );
      final sub = container.listen(
        commandTimelineControllerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      addTearDown(container.dispose);

      await container
          .read(commandTimelineControllerProvider.notifier)
          .initialize(<String, dynamic>{'id': 'cmd-cached'});

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(commandTimelineControllerProvider);
      expect(state.loadedFromCache, isTrue);
      expect(state.status, CommandExecutionStatus.failed);
      expect(state.command['id'], 'cmd-cached');
      expect(fakeRepository.savedResults, isEmpty);
    });
  });
}
