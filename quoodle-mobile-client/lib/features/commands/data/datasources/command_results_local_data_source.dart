import 'package:secure_device_control/features/commands/data/dtos/command_result_record_dto.dart';
import 'package:secure_device_control/features/commands/data/services/command_results_database.dart';

class CommandResultsLocalDataSource {
  CommandResultsLocalDataSource({CommandResultsDatabase? database})
      : _database = database ?? CommandResultsDatabase();

  final CommandResultsDatabase _database;

  Future<CommandResultRecordDto?> loadResult(String commandId) async {
    final record = await _database.loadResult(commandId);
    if (record == null) {
      return null;
    }

    return CommandResultRecordDto(
      commandId: record.commandId,
      method: record.method,
      deviceId: record.deviceId,
      deviceName: record.deviceName,
      initiator: record.initiator,
      status: record.status,
      commandData: record.commandData,
      savedAt: record.savedAt,
    );
  }

  Future<void> saveResult(CommandResultRecordDto result) {
    return _database.saveResult(
      CommandResultRecord(
        commandId: result.commandId,
        method: result.method,
        deviceId: result.deviceId,
        deviceName: result.deviceName,
        initiator: result.initiator,
        status: result.status,
        commandData: result.commandData,
        savedAt: result.savedAt,
      ),
    );
  }
}
