import 'package:secure_device_control/features/commands/data/datasources/command_results_local_data_source.dart';
import 'package:secure_device_control/features/commands/data/mappers/command_result_mapper.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_result.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';

class CommandTimelineRepositoryImpl implements CommandTimelineRepository {
  const CommandTimelineRepositoryImpl(this._localDataSource);

  final CommandResultsLocalDataSource _localDataSource;

  @override
  Future<CommandResult?> loadResult(String commandId) async {
    final dto = await _localDataSource.loadResult(commandId);
    return dto?.toDomain();
  }

  @override
  Future<void> saveResult(CommandResult result) {
    return _localDataSource.saveResult(result.toDto());
  }
}
