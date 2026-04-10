import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/scheduler/data/services/scheduler_service.dart';

final schedulerServiceProvider =
    ChangeNotifierProvider<SchedulerService>((ref) {
  return SchedulerService();
});

final schedulerInitializationProvider = FutureProvider<void>((ref) async {
  await ref.read(schedulerServiceProvider).initialize();
});
