import 'package:secure_device_control/features/commands/data/dtos/command_result_record_dto.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';

extension CommandResultRecordDtoToDomain on CommandResultRecordDto {
  CommandResult toDomain() {
    return CommandResult(
      commandId: commandId,
      method: method,
      deviceId: deviceId,
      deviceName: deviceName,
      initiator: initiator,
      status: _statusFromString(status),
      commandData: commandData,
      savedAt: savedAt,
    );
  }
}

extension CommandResultToDto on CommandResult {
  CommandResultRecordDto toDto() {
    return CommandResultRecordDto(
      commandId: commandId,
      method: method,
      deviceId: deviceId,
      deviceName: deviceName,
      initiator: initiator,
      status: status.name,
      commandData: commandData,
      savedAt: savedAt,
    );
  }
}

CommandExecutionStatus _statusFromString(String value) {
  switch (value) {
    case 'queued':
      return CommandExecutionStatus.queued;
    case 'dispatched':
      return CommandExecutionStatus.dispatched;
    case 'acked':
      return CommandExecutionStatus.acked;
    case 'completed':
      return CommandExecutionStatus.completed;
    case 'failed':
      return CommandExecutionStatus.failed;
    case 'expired':
      return CommandExecutionStatus.expired;
    case 'executing':
    default:
      return CommandExecutionStatus.executing;
  }
}
