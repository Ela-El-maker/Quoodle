import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';

class CommandTimelineState {
  const CommandTimelineState({
    required this.command,
    required this.status,
    required this.loadedFromCache,
    required this.secondsSinceUpdate,
    required this.pollCount,
    required this.initialized,
  });

  factory CommandTimelineState.initial() {
    return const CommandTimelineState(
      command: _defaultCommand,
      status: CommandExecutionStatus.executing,
      loadedFromCache: false,
      secondsSinceUpdate: 0,
      pollCount: 0,
      initialized: false,
    );
  }

  final Map<String, dynamic> command;
  final CommandExecutionStatus status;
  final bool loadedFromCache;
  final int secondsSinceUpdate;
  final int pollCount;
  final bool initialized;

  bool get isTerminal =>
      status == CommandExecutionStatus.completed ||
      status == CommandExecutionStatus.failed ||
      status == CommandExecutionStatus.expired;

  CommandTimelineState copyWith({
    Map<String, dynamic>? command,
    CommandExecutionStatus? status,
    bool? loadedFromCache,
    int? secondsSinceUpdate,
    int? pollCount,
    bool? initialized,
  }) {
    return CommandTimelineState(
      command: command ?? this.command,
      status: status ?? this.status,
      loadedFromCache: loadedFromCache ?? this.loadedFromCache,
      secondsSinceUpdate: secondsSinceUpdate ?? this.secondsSinceUpdate,
      pollCount: pollCount ?? this.pollCount,
      initialized: initialized ?? this.initialized,
    );
  }
}

const Map<String, dynamic> _defaultCommand = {
  'id': 'cmd-0091',
  'method': 'policy_sync',
  'deviceId': 'dev-007',
  'deviceName': 'WKS-FINANCE-07',
  'initiator': 'L. Nakamura',
  'role': 'operator',
  'sensitive': false,
  'params': '{"force": true, "version": "1.0.4"}',
  'policyDecision': 'allow',
  'queuedAt': '2026-04-06T10:41:03Z',
  'dispatchedAt': '2026-04-06T10:41:04Z',
  'ackedAt': '2026-04-06T10:41:05Z',
  'executingAt': '2026-04-06T10:41:06Z',
};
