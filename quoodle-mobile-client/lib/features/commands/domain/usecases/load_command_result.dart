import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';

class LoadCommandResult {
  const LoadCommandResult(this._repository);

  final CommandTimelineRepository _repository;

  Future<CommandResult?> call(String commandId) {
    return _repository.loadResult(commandId);
  }
}
