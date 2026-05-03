import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/features/devices/data/datasources/device_telemetry_remote_data_source.dart';
import 'package:secure_device_control/features/devices/data/datasources/devices_remote_data_source.dart';
import 'package:secure_device_control/features/devices/data/repositories/devices_repository_impl.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';
import 'package:secure_device_control/features/devices/domain/usecases/get_device_by_id.dart';
import 'package:secure_device_control/features/devices/domain/usecases/get_devices.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_controller.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_state.dart';

final devicesRemoteDataSourceProvider =
    Provider<DevicesRemoteDataSource>((ref) {
  return DevicesRemoteDataSource(ref.read(apiClientProvider));
});

final deviceTelemetryRemoteDataSourceProvider =
    Provider<DeviceTelemetryRemoteDataSource>((ref) {
  return DeviceTelemetryRemoteDataSource(ref.read(apiClientProvider));
});

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  return DevicesRepositoryImpl(ref.read(devicesRemoteDataSourceProvider));
});

final getDevicesProvider = Provider<GetDevices>((ref) {
  return GetDevices(ref.read(devicesRepositoryProvider));
});

final getDeviceByIdProvider = Provider<GetDeviceById>((ref) {
  return GetDeviceById(ref.read(devicesRepositoryProvider));
});

final devicesControllerProvider =
    AutoDisposeNotifierProvider<DevicesController, DevicesState>(
  DevicesController.new,
);

final deviceDetailProvider = Provider.family<DeviceEntity?, String>((ref, id) {
  return ref.read(getDeviceByIdProvider).call(id);
});

final deviceDetailAsyncProvider =
    FutureProvider.family<DeviceEntity?, String>((ref, id) async {
  final cached = ref.read(getDeviceByIdProvider).call(id);
  if (cached != null) {
    return cached;
  }

  final result = await ref.read(getDevicesProvider).call();
  return result.when(
    success: (devices) {
      for (final device in devices) {
        if (device.id == id) {
          return device;
        }
      }
      return null;
    },
    failure: (_) => null,
  );
});
