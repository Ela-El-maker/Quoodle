import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';

class SaveCommandResult {
  const SaveCommandResult(this._repository);

  final CommandTimelineRepository _repository;

  Future<void> call(CommandResult result) {
    return _repository.saveResult(result);
  }
}
