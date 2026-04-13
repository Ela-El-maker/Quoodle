import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';

abstract class DevicesRepository {
  Future<Result<List<DeviceEntity>>> getDevices();

  DeviceEntity? getDeviceById(String id);
}
