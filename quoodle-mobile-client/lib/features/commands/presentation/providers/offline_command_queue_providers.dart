import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/data/services/offline_command_queue.dart';

final offlineCommandQueueProvider =
    ChangeNotifierProvider<OfflineCommandQueue>((ref) {
  return OfflineCommandQueue();
});

final offlineCommandQueueInitializationProvider = FutureProvider<void>((
  ref,
) async {
  await ref.read(offlineCommandQueueProvider).initialize();
});
