import 'package:secure_device_control/features/devices/data/datasources/devices_local_data_source.dart';
import 'package:secure_device_control/features/devices/data/mappers/device_mapper.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';

class DevicesRepositoryImpl implements DevicesRepository {
  const DevicesRepositoryImpl(this._localDataSource);

  final DevicesLocalDataSource _localDataSource;

  @override
  List<DeviceEntity> getDevices() {
    return _localDataSource.getDevices().map((dto) => dto.toDomain()).toList();
  }

  @override
  DeviceEntity? getDeviceById(String id) {
    final devices = getDevices();
    for (final device in devices) {
      if (device.id == id) {
        return device;
      }
    }
    return null;
  }
}
