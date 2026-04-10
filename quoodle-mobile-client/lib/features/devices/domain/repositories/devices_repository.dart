import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';

abstract class DevicesRepository {
  List<DeviceEntity> getDevices();

  DeviceEntity? getDeviceById(String id);
}
