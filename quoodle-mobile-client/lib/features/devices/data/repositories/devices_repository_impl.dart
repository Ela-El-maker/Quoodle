import 'package:secure_device_control/core/errors/failure_mapper.dart';
import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/devices/data/datasources/devices_remote_data_source.dart';
import 'package:secure_device_control/features/devices/data/mappers/device_mapper.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';

class DevicesRepositoryImpl implements DevicesRepository {
  DevicesRepositoryImpl(this._remoteDataSource);

  final DevicesRemoteDataSource _remoteDataSource;
  List<DeviceEntity> _cachedDevices = const <DeviceEntity>[];

  @override
  Future<Result<List<DeviceEntity>>> getDevices() async {
    try {
      final dtos = await _remoteDataSource.fetchDevices();
      final devices = dtos.map((dto) => dto.toDomain()).toList();
      _cachedDevices = devices;
      return Success<List<DeviceEntity>>(devices);
    } on Object catch (error) {
      return FailureResult<List<DeviceEntity>>(FailureMapper.fromObject(error));
    }
  }

  @override
  DeviceEntity? getDeviceById(String id) {
    for (final device in _cachedDevices) {
      if (device.id == id) {
        return device;
      }
    }
    return null;
  }
}
