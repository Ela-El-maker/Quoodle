import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/devices/data/datasources/devices_local_data_source.dart';
import 'package:secure_device_control/features/devices/data/repositories/devices_repository_impl.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';
import 'package:secure_device_control/features/devices/domain/usecases/get_device_by_id.dart';
import 'package:secure_device_control/features/devices/domain/usecases/get_devices.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_controller.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_state.dart';

final devicesLocalDataSourceProvider = Provider<DevicesLocalDataSource>((ref) {
  return const DevicesLocalDataSource();
});

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  return DevicesRepositoryImpl(ref.read(devicesLocalDataSourceProvider));
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
