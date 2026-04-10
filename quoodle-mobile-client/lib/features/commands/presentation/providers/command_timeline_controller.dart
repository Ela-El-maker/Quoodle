import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_providers.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_state.dart';

class CommandTimelineController
    extends AutoDisposeNotifier<CommandTimelineState> {
  static const Map<String, String> _methodResultTypes = {
    'screenshot_capture': 'screenshot',
    'process_list': 'process_list',
    'system_info': 'system_info',
    'running_apps': 'running_apps',
    'filesystem': 'filesystem',
    'network_info': 'network_info',
    'upload_file': 'file_op',
    'create_file': 'file_op',
    'collect_telemetry': 'telemetry',
  };

  Timer? _pollTimer;
  Timer? _secondsTimer;
  bool _savedToDb = false;

  @override
  CommandTimelineState build() {
    ref.onDispose(_cancelTimers);
    return CommandTimelineState.initial();
  }

  Future<void> initialize(Object? routeArguments) async {
    if (state.initialized) {
      return;
    }

    _savedToDb = false;
    final command = _buildCommand(routeArguments);

    state = state.copyWith(
      command: command,
      status: CommandExecutionStatus.executing,
      loadedFromCache: false,
      secondsSinceUpdate: 0,
      pollCount: 0,
      initialized: true,
    );

    _startTicking();
    _startPolling();
    await _tryRestoreFromStorage(command['id'] as String? ?? 'cmd-0091');
  }

  Future<void> _tryRestoreFromStorage(String commandId) async {
    try {
      final persisted =
          await ref.read(loadCommandResultProvider).call(commandId);
      if (persisted == null) {
        return;
      }

      _savedToDb = true;
      _cancelTimers();
      state = state.copyWith(
        command: persisted.commandData,
        status: persisted.status,
        loadedFromCache: true,
        secondsSinceUpdate: 0,
      );
    } catch (_) {
      // Keep live polling behavior if local restore fails.
    }
  }

  void _startTicking() {
    _secondsTimer?.cancel();
    _secondsTimer = Timer.periodic(
      ref.read(commandTimelineTickIntervalProvider),
      (_) {
        if (!state.initialized) {
          return;
        }
        state =
            state.copyWith(secondsSinceUpdate: state.secondsSinceUpdate + 1);
      },
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      ref.read(commandTimelinePollIntervalProvider),
      (_) async {
        if (!state.initialized || state.loadedFromCache) {
          return;
        }

        final nextPollCount = state.pollCount + 1;
        state = state.copyWith(pollCount: nextPollCount);

        if (nextPollCount < ref.read(commandTimelinePollThresholdProvider) ||
            state.status != CommandExecutionStatus.executing) {
          return;
        }

        final method = state.command['method'] as String? ?? 'policy_sync';
        final resultType = _methodResultTypes[method];

        final updatedCommand = <String, dynamic>{
          ...state.command,
          'completedAt': '2026-04-06T10:41:14Z',
          'executionTimeMs': 8210,
          'resultStatus': 'success',
          'resultNotes': 'Command executed successfully.',
          if (resultType != null) 'resultType': resultType,
        };

        state = state.copyWith(
          status: CommandExecutionStatus.completed,
          command: updatedCommand,
          secondsSinceUpdate: 0,
        );

        _pollTimer?.cancel();
        await _persistResult();
      },
    );
  }

  Future<void> _persistResult() async {
    if (_savedToDb || state.command.isEmpty) {
      return;
    }

    final result = CommandResult(
      commandId: state.command['id'] as String? ?? 'cmd-unknown',
      method: state.command['method'] as String? ?? '',
      deviceId: state.command['deviceId'] as String? ?? '',
      deviceName: state.command['deviceName'] as String? ?? '',
      initiator: state.command['initiator'] as String? ?? '',
      status: state.status,
      commandData: Map<String, dynamic>.from(state.command),
      savedAt: DateTime.now(),
    );

    try {
      await ref.read(saveCommandResultProvider).call(result);
      _savedToDb = true;
    } catch (_) {
      // Preserve UX flow even when local persistence fails.
    }
  }

  Map<String, dynamic> _buildCommand(Object? routeArguments) {
    final args = routeArguments is Map
        ? Map<String, dynamic>.from(argsToMap(routeArguments))
        : const <String, dynamic>{};

    final params = args['params'];
    final normalizedParams = params is Map
        ? jsonEncode(params)
        : (params?.toString() ??
            CommandTimelineState.initial().command['params']);

    return <String, dynamic>{
      ...CommandTimelineState.initial().command,
      if (args.containsKey('method')) 'method': args['method'],
      if (args.containsKey('sensitive')) 'sensitive': args['sensitive'],
      if (args.containsKey('id')) 'id': args['id'],
      if (args.containsKey('initiator')) 'initiator': args['initiator'],
      if (args.containsKey('deviceId')) 'deviceId': args['deviceId'],
      if (args.containsKey('deviceName')) 'deviceName': args['deviceName'],
      'params': normalizedParams,
    };
  }

  Map<dynamic, dynamic> argsToMap(Map<dynamic, dynamic> args) {
    return args;
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _secondsTimer?.cancel();
    _pollTimer = null;
    _secondsTimer = null;
  }
}
