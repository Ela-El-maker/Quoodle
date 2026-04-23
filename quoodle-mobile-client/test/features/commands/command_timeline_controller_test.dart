import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/features/commands/data/datasources/commands_remote_data_source.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
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

class _FakeApiClient implements ApiClient {
  _FakeApiClient({
    Map<String, dynamic>? singleGetResponse,
    bool throwOnGet = false,
  })  : _singleGetResponse = singleGetResponse,
        _throwOnGet = throwOnGet;

  final Map<String, dynamic>? _singleGetResponse;
  final bool _throwOnGet;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    if (_throwOnGet) {
      throw Exception('network_error');
    }
    return _singleGetResponse ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    return <String, dynamic>{};
  }
}

void main() {
  group('CommandTimelineController', () {
    test('polls to completion and persists result', () async {
      final fakeRepository = _FakeCommandTimelineRepository();
      final fakeApi = _FakeApiClient(
        singleGetResponse: <String, dynamic>{
          'command_id': 'cmd-test-1',
          'device_id': 'dev-007',
          'device_name': 'WKS-FINANCE-07',
          'method': 'policy_sync',
          'params': <String, dynamic>{'force': true},
          'state': 'completed',
          'execution_state': 'completed',
          'queued_at': '2026-04-11T10:41:00Z',
          'dispatched_at': '2026-04-11T10:41:01Z',
          'completed_at': '2026-04-11T10:41:02Z',
          'result_status': 'success',
          'result_notes': 'Command executed successfully.',
          'actor_email': 'operator@example.com',
        },
      );

      final container = ProviderContainer(
        overrides: [
          commandTimelineRepositoryProvider.overrideWithValue(fakeRepository),
          commandsRemoteDataSourceProvider.overrideWithValue(
            CommandsRemoteDataSource(fakeApi),
          ),
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
      final fakeApi = _FakeApiClient(throwOnGet: true);

      final container = ProviderContainer(
        overrides: [
          commandTimelineRepositoryProvider.overrideWithValue(fakeRepository),
          commandsRemoteDataSourceProvider.overrideWithValue(
            CommandsRemoteDataSource(fakeApi),
          ),
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
