import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/data/services/offline_command_queue.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';

final offlineCommandQueueProvider =
    ChangeNotifierProvider<OfflineCommandQueue>((ref) {
  final queue = OfflineCommandQueue();
  queue.configureDispatcher(
    ({
      required String deviceId,
      required String method,
      required Map<String, dynamic> params,
      required bool sensitive,
    }) {
      return ref.read(commandsRemoteDataSourceProvider).dispatchCommand(
            deviceId: deviceId,
            method: method,
            params: params,
            sensitive: sensitive,
          );
    },
  );
  return queue;
});

final offlineCommandQueueInitializationProvider = FutureProvider<void>((
  ref,
) async {
  await ref.read(offlineCommandQueueProvider).initialize();
});
