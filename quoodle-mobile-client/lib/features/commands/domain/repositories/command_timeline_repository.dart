import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';

abstract class CommandTimelineRepository {
  Future<CommandResult?> loadResult(String commandId);

  Future<void> saveResult(CommandResult result);
}
