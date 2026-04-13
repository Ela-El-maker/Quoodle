import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/endpoints.dart';
import 'package:secure_device_control/features/devices/data/dtos/device_dto.dart';

class DevicesRemoteDataSource {
  const DevicesRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<DeviceDto>> fetchDevices() async {
    final devices = <DeviceDto>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await _apiClient.get(
        Endpoints.devices,
        queryParameters: <String, dynamic>{
          'page': page,
          'per_page': 200,
        },
      );

      final rawDevices = response['devices'];
      if (rawDevices is List) {
        for (final item in rawDevices) {
          if (item is Map) {
            devices.add(
              DeviceDto.fromMap(_asStringDynamicMap(item)),
            );
          }
        }
      }

      final meta = response['meta'];
      if (meta is Map) {
        final metaMap = _asStringDynamicMap(meta);
        final currentPage = _toInt(metaMap['current_page']) ?? page;
        lastPage = _toInt(metaMap['last_page']) ?? currentPage;
        page = currentPage + 1;
      } else {
        break;
      }
    } while (page <= lastPage);

    return devices;
  }

  Map<String, dynamic> _asStringDynamicMap(Map<dynamic, dynamic> map) {
    return map.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
