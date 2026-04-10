import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/data/datasources/command_results_local_data_source.dart';
import 'package:secure_device_control/features/commands/data/repositories/command_timeline_repository_impl.dart';
import 'package:secure_device_control/features/commands/domain/repositories/command_timeline_repository.dart';
import 'package:secure_device_control/features/commands/domain/usecases/load_command_result.dart';
import 'package:secure_device_control/features/commands/domain/usecases/save_command_result.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_controller.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_state.dart';

final commandResultsLocalDataSourceProvider =
    Provider<CommandResultsLocalDataSource>((ref) {
  return CommandResultsLocalDataSource();
});

final commandTimelineRepositoryProvider = Provider<CommandTimelineRepository>((
  ref,
) {
  return CommandTimelineRepositoryImpl(
    ref.read(commandResultsLocalDataSourceProvider),
  );
});

final loadCommandResultProvider = Provider<LoadCommandResult>((ref) {
  return LoadCommandResult(ref.read(commandTimelineRepositoryProvider));
});

final saveCommandResultProvider = Provider<SaveCommandResult>((ref) {
  return SaveCommandResult(ref.read(commandTimelineRepositoryProvider));
});

final commandTimelinePollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 2);
});

final commandTimelineTickIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 1);
});

final commandTimelinePollThresholdProvider = Provider<int>((ref) {
  return 3;
});

final commandTimelineControllerProvider = AutoDisposeNotifierProvider<
    CommandTimelineController, CommandTimelineState>(
  CommandTimelineController.new,
);
