import '../models/telemetry.dart';
import 'api_service.dart';

class TelemetryService {
  TelemetryService(this._api);

  final ApiService _api;

  Future<TelemetrySnapshot> latest(String deviceId) => _api.fetchLatestTelemetry(deviceId);

  Future<List<TelemetryPoint>> history(String deviceId, {required String from, required String to}) =>
      _api.fetchTelemetryHistory(deviceId, from: from, to: to);
}
