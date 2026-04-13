import 'dart:math';

import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/endpoints.dart';

class CommandsRemoteDataSource {
  const CommandsRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> dispatchCommand({
    required String deviceId,
    required String method,
    required Map<String, dynamic> params,
    required bool sensitive,
    String? twoFactorCode,
  }) {
    final payload = <String, dynamic>{
      'client_message_id': _buildClientMessageId(),
      'device_id': deviceId,
      'method': method,
      'params': params,
      'sensitive': sensitive,
      if (twoFactorCode != null && twoFactorCode.isNotEmpty)
        'two_factor_code': twoFactorCode,
    };
    return _apiClient.post(Endpoints.commands, data: payload);
  }

  Future<Map<String, dynamic>> fetchCommand(String commandId) {
    return _apiClient.get(Endpoints.commandById(commandId));
  }

  Future<List<Map<String, dynamic>>> fetchDeviceCommands(
    String deviceId, {
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      Endpoints.deviceCommands(deviceId),
      queryParameters: <String, dynamic>{'limit': limit},
    );
    final raw = response['commands'];
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) => _asStringDynamicMap(entry))
        .toList(growable: false);
  }

  Map<String, dynamic> _asStringDynamicMap(Map<dynamic, dynamic> value) {
    return value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue),
    );
  }

  String _buildClientMessageId() {
    final random = Random.secure();
    final epoch = DateTime.now().millisecondsSinceEpoch;
    final suffix = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'mob-$epoch-$suffix';
  }
}
