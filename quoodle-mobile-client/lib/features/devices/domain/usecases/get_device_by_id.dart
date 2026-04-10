import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';

class GetDeviceById {
  const GetDeviceById(this._repository);

  final DevicesRepository _repository;

  DeviceEntity? call(String id) {
    return _repository.getDeviceById(id);
  }
}
