import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/endpoints.dart';

class DeviceTelemetryRemoteDataSource {
  const DeviceTelemetryRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> fetchLatestTelemetry(String deviceId) {
    return _apiClient.get(Endpoints.telemetryDeviceLatest(deviceId));
  }

  Future<Map<String, dynamic>> fetchTelemetryHistory(
    String deviceId, {
    DateTime? from,
    DateTime? to,
    int limit = 1000,
  }) {
    final query = <String, dynamic>{
      'limit': limit,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    };
    return _apiClient.get(
      Endpoints.telemetryDeviceHistory(deviceId),
      queryParameters: query,
    );
  }
}
