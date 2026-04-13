import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_providers.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_state.dart';

class CommandTimelineController
    extends AutoDisposeNotifier<CommandTimelineState> {
  Timer? _pollTimer;
  Timer? _secondsTimer;
  bool _savedToDb = false;
  bool _refreshInFlight = false;
  String? _commandId;

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
    _commandId = _asString(command['id']).ifEmptyNull();
    final initialStatus =
        _statusFromApiState(_asString(command['executionState']).ifEmpty(
      _asString(command['state']).ifEmpty('executing'),
    ));

    state = state.copyWith(
      command: command,
      status: initialStatus,
      loadedFromCache: false,
      secondsSinceUpdate: 0,
      pollCount: 0,
      initialized: true,
    );

    _startTicking();
    if (_commandId == null) {
      return;
    }

    await _tryRestoreFromStorage(_commandId!);
    await _refreshFromApi();
    _startPolling();
  }

  Future<void> _tryRestoreFromStorage(String commandId) async {
    try {
      final persisted =
          await ref.read(loadCommandResultProvider).call(commandId);
      if (persisted == null) {
        return;
      }

      _savedToDb = true;
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
        state = state.copyWith(
          secondsSinceUpdate: state.secondsSinceUpdate + 1,
        );
      },
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      ref.read(commandTimelinePollIntervalProvider),
      (_) => _refreshFromApi(),
    );
  }

  Future<void> _refreshFromApi() async {
    if (!state.initialized ||
        _refreshInFlight ||
        _commandId == null ||
        _commandId!.isEmpty) {
      return;
    }
    if (state.isTerminal) {
      _cancelTimers();
      await _persistResult();
      return;
    }

    _refreshInFlight = true;
    try {
      final payload =
          await ref.read(commandsRemoteDataSourceProvider).fetchCommand(
                _commandId!,
              );
      final mapped = _mapApiCommand(payload, fallback: state.command);
      state = state.copyWith(
        command: mapped.$1,
        status: mapped.$2,
        loadedFromCache: false,
        secondsSinceUpdate: 0,
        pollCount: state.pollCount + 1,
      );

      if (state.isTerminal) {
        _cancelTimers();
        await _persistResult();
      }
    } catch (_) {
      // Keep polling silently; UI already shows the latest known command state.
    } finally {
      _refreshInFlight = false;
    }
  }

  (Map<String, dynamic>, CommandExecutionStatus) _mapApiCommand(
    Map<String, dynamic> payload, {
    required Map<String, dynamic> fallback,
  }) {
    final executionState = _asString(payload['execution_state']);
    final stateRaw = executionState.ifEmpty(_asString(payload['state']));
    final status = _statusFromApiState(stateRaw);

    final queuedAt = _asString(payload['queued_at']).ifEmpty(
      _asString(fallback['queuedAt']),
    );
    final dispatchedAt = _asString(payload['dispatched_at']).ifEmpty(
      _asString(fallback['dispatchedAt']),
    );
    final completedAt = _asString(payload['completed_at']).ifEmpty(
      _asString(fallback['completedAt']),
    );
    final ackedAt = _deriveAckedAt(status, dispatchedAt, queuedAt, fallback);
    final executingAt =
        _deriveExecutingAt(status, dispatchedAt, ackedAt, fallback);

    final result = _asStringDynamicMap(payload['result']);
    final fallbackResult = _asStringDynamicMap(fallback['result']);
    final effectiveResult = result.isEmpty ? fallbackResult : result;
    final resultStatus = _asString(payload['result_status']).ifEmpty(
      _asString(result['status']),
    );
    final resultNotes = _asString(payload['result_notes'])
        .ifEmpty(_asString(result['notes']))
        .ifEmpty(_asString(payload['reason']))
        .ifEmpty(_asString(fallback['resultNotes']));

    final paramsValue = payload['params'];
    final paramsString = paramsValue is Map || paramsValue is List
        ? jsonEncode(paramsValue)
        : _asString(paramsValue).ifEmpty(_asString(fallback['params']));

    final executionTimeMs = _toInt(
          result['execution_time_ms'],
        ) ??
        _toInt(result['duration_ms']) ??
        _toInt(result['elapsed_ms']) ??
        _computeExecutionMs(queuedAt, completedAt) ??
        _toInt(fallback['executionTimeMs']);

    final policyDecision = status == CommandExecutionStatus.failed
        ? 'deny'
        : _asString(fallback['policyDecision']).ifEmpty('allow');

    final mapped = <String, dynamic>{
      ...fallback,
      'id': _asString(payload['command_id']).ifEmpty(_asString(fallback['id'])),
      'method':
          _asString(payload['method']).ifEmpty(_asString(fallback['method'])),
      'deviceId': _asString(payload['device_id']).ifEmpty(
        _asString(fallback['deviceId']),
      ),
      'deviceName': _asString(payload['device_name']).ifEmpty(
        _asString(fallback['deviceName']),
      ),
      'initiator': _asString(payload['actor_email']).ifEmpty(
        _asString(fallback['initiator']).ifEmpty('Operator'),
      ),
      'role': _asString(fallback['role']).ifEmpty('operator'),
      'sensitive': fallback['sensitive'] == true,
      'params': paramsString,
      'policyDecision': policyDecision,
      'state': _asString(payload['state']).ifEmpty(stateRaw),
      'executionState': stateRaw,
      'queuedAt': queuedAt,
      'dispatchedAt': dispatchedAt,
      'ackedAt': ackedAt,
      'executingAt': executingAt,
      'completedAt': completedAt,
      'result': effectiveResult,
      'resultStatus': resultStatus,
      'resultNotes': resultNotes,
      'artifactUrl': _asString(payload['artifact_url']).ifEmpty(
        _asString(result['artifact_url']),
      ),
      'artifactChecksum': _asString(payload['artifact_checksum']).ifEmpty(
        _asString(result['artifact_checksum']),
      ),
      'errorCode': _asString(payload['error_code']).ifEmpty(
        _asString(fallback['errorCode']),
      ),
      'errorMessage': _asString(payload['error_message'])
          .ifEmpty(_asString(payload['reason']))
          .ifEmpty(_asString(fallback['errorMessage'])),
      if (executionTimeMs != null) 'executionTimeMs': executionTimeMs,
    };

    return (mapped, status);
  }

  String _deriveAckedAt(
    CommandExecutionStatus status,
    String dispatchedAt,
    String queuedAt,
    Map<String, dynamic> fallback,
  ) {
    if (status == CommandExecutionStatus.queued ||
        status == CommandExecutionStatus.dispatched) {
      return _asString(fallback['ackedAt']);
    }
    return dispatchedAt
        .ifEmpty(queuedAt)
        .ifEmpty(_asString(fallback['ackedAt']));
  }

  String _deriveExecutingAt(
    CommandExecutionStatus status,
    String dispatchedAt,
    String ackedAt,
    Map<String, dynamic> fallback,
  ) {
    if (status == CommandExecutionStatus.queued ||
        status == CommandExecutionStatus.dispatched ||
        status == CommandExecutionStatus.acked) {
      return _asString(fallback['executingAt']);
    }
    return ackedAt
        .ifEmpty(dispatchedAt)
        .ifEmpty(_asString(fallback['executingAt']));
  }

  int? _computeExecutionMs(String queuedAt, String completedAt) {
    if (queuedAt.isEmpty || completedAt.isEmpty) {
      return null;
    }
    final queued = DateTime.tryParse(queuedAt);
    final completed = DateTime.tryParse(completedAt);
    if (queued == null || completed == null) {
      return null;
    }
    final duration = completed.toUtc().difference(queued.toUtc());
    if (duration.isNegative) {
      return null;
    }
    return duration.inMilliseconds;
  }

  CommandExecutionStatus _statusFromApiState(String rawState) {
    switch (rawState) {
      case 'queued':
        return CommandExecutionStatus.queued;
      case 'dispatched':
      case 'sent':
        return CommandExecutionStatus.dispatched;
      case 'ack_received':
      case 'acked':
      case 'acknowledged':
        return CommandExecutionStatus.acked;
      case 'executing':
      case 'partial':
        return CommandExecutionStatus.executing;
      case 'completed':
        return CommandExecutionStatus.completed;
      case 'failed':
      case 'rejected':
        return CommandExecutionStatus.failed;
      case 'expired':
        return CommandExecutionStatus.expired;
      default:
        return CommandExecutionStatus.executing;
    }
  }

  Future<void> _persistResult() async {
    if (_savedToDb || state.command.isEmpty) {
      return;
    }

    final result = CommandResult(
      commandId: _asString(state.command['id']).ifEmpty('cmd-unknown'),
      method: _asString(state.command['method']),
      deviceId: _asString(state.command['deviceId']),
      deviceName: _asString(state.command['deviceName']),
      initiator: _asString(state.command['initiator']),
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
        ? Map<String, dynamic>.from(routeArguments.cast<Object?, Object?>())
        : const <String, dynamic>{};

    final paramsValue = args['params'];
    final params = paramsValue is Map || paramsValue is List
        ? jsonEncode(paramsValue)
        : _asString(paramsValue).ifEmpty(
            _asString(CommandTimelineState.initial().command['params']));

    return <String, dynamic>{
      ...CommandTimelineState.initial().command,
      if (args.containsKey('id')) 'id': args['id'],
      if (args.containsKey('method')) 'method': args['method'],
      if (args.containsKey('deviceId')) 'deviceId': args['deviceId'],
      if (args.containsKey('deviceName')) 'deviceName': args['deviceName'],
      if (args.containsKey('initiator')) 'initiator': args['initiator'],
      if (args.containsKey('role')) 'role': args['role'],
      if (args.containsKey('sensitive')) 'sensitive': args['sensitive'],
      if (args.containsKey('policyDecision'))
        'policyDecision': args['policyDecision'],
      if (args.containsKey('queuedAt')) 'queuedAt': args['queuedAt'],
      if (args.containsKey('state')) 'state': args['state'],
      if (args.containsKey('executionState'))
        'executionState': args['executionState'],
      'params': params,
    };
  }

  Map<String, dynamic> _asStringDynamicMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return const <String, dynamic>{};
  }

  String _asString(Object? value) {
    if (value is String) {
      return value;
    }
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _secondsTimer?.cancel();
    _pollTimer = null;
    _secondsTimer = null;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
  String? ifEmptyNull() => isEmpty ? null : this;
}
