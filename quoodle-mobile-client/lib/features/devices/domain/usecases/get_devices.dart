import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';

class GetDevices {
  const GetDevices(this._repository);

  final DevicesRepository _repository;

  List<DeviceEntity> call() {
    return _repository.getDevices();
  }
}
