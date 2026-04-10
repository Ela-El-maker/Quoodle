import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';

class CommandResult {
  const CommandResult({
    required this.commandId,
    required this.method,
    required this.deviceId,
    required this.deviceName,
    required this.initiator,
    required this.status,
    required this.commandData,
    required this.savedAt,
  });

  final String commandId;
  final String method;
  final String deviceId;
  final String deviceName;
  final String initiator;
  final CommandExecutionStatus status;
  final Map<String, dynamic> commandData;
  final DateTime savedAt;
}
