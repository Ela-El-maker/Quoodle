import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/features/commands/data/datasources/commands_remote_data_source.dart';

final commandsRemoteDataSourceProvider = Provider<CommandsRemoteDataSource>((
  ref,
) {
  return CommandsRemoteDataSource(ref.read(apiClientProvider));
});
