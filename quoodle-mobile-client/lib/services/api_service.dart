import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/environment.dart';
import '../models/alert.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../models/telemetry.dart';
import '../models/update_status.dart';
import 'session_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  Map<String, dynamic>? get jsonBody {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  String? get reason {
    final j = jsonBody;
    if (j == null) return null;
    return j['reason'] as String?;
  }

  @override
  String toString() => 'API error $statusCode: $body';
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${Environment.apiBaseUrl}$path');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (SessionStore.jwt != null && SessionStore.jwt!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${SessionStore.jwt}';
    }
    final resp = await _client.post(
      _uri(path),
      headers: headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final headers = <String, String>{};
    if (SessionStore.jwt != null && SessionStore.jwt!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${SessionStore.jwt}';
    }
    final resp = await _client.get(_uri(path), headers: headers);
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String displayName,
    required String email,
    required String password,
    required String pubkey,
  }) {
    return _post('/register', {
      'display_name': displayName,
      'email': email,
      'password': password,
      'pubkey': pubkey,
    });
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? twoFactorCode,
    String? deviceFingerprint,
    String? pushToken,
  }) {
    return _post('/login', {
      'email': email,
      'password': password,
      'device_fingerprint': deviceFingerprint ?? 'mobile-device',
      'push_token': pushToken,
      'two_factor_code': twoFactorCode,
    });
  }

  Future<Map<String, dynamic>> verify2fa({
    required String userId,
    required String sessionId,
    required String code,
  }) {
    return _post('/2fa/verify', {
      'user_id': userId,
      'session_id': sessionId,
      'two_factor_code': code,
    });
  }

  Future<Map<String, dynamic>> setup2fa(
      {required String userId, required String sessionId}) {
    return _post('/2fa/setup', {
      'user_id': userId,
      'session_id': sessionId,
    });
  }

  Future<Map<String, dynamic>> confirm2fa({
    required String userId,
    required String sessionId,
    required String code,
  }) {
    return _post('/2fa/confirm', {
      'user_id': userId,
      'session_id': sessionId,
      'two_factor_code': code,
    });
  }

  Future<List<Device>> fetchDevices() async {
    final json = await _get('/devices');
    final list = (json['devices'] as List<dynamic>? ?? []);
    return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Device>> fetchUnpairedDevices(
      {required String userId, required String sessionId}) async {
    final json =
        await _get('/devices/unpaired?user_id=$userId&session_id=$sessionId');
    final list = (json['devices'] as List<dynamic>? ?? []);
    return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> claimDevice({
    required String deviceId,
    required String userId,
    required String sessionId,
  }) {
    return _post('/devices/$deviceId/claim', {
      'user_id': userId,
      'session_id': sessionId,
    });
  }

  Future<Device> fetchDevice(String deviceId) async {
    final json = await _get('/devices/$deviceId');
    return Device.fromJson(json);
  }

  Future<Map<String, dynamic>> initPairing({String? deviceLabel}) {
    return _post('/pair/init', {'device_label': deviceLabel});
  }

  Future<Map<String, dynamic>> confirmPairing(
      {required String pairToken, String? pairSessionId}) {
    return _post('/pair/confirm',
        {'pair_token': pairToken, 'pair_session_id': pairSessionId});
  }

  Future<CommandState> sendCommand({
    required String deviceId,
    required String method,
    required Map<String, dynamic> params,
    required bool sensitive,
    required String clientMessageId,
    String? twoFactorCode,
  }) async {
    final json = await _post('/commands', {
      'device_id': deviceId,
      'method': method,
      'params': params,
      'sensitive': sensitive,
      'client_message_id': clientMessageId,
      'two_factor_code': twoFactorCode,
      'user_id': SessionStore.userId,
    });
    return CommandState.fromJson(json);
  }

  Future<List<CommandState>> fetchDeviceCommands(String deviceId) async {
    final json = await _get('/devices/$deviceId/commands');
    final commands = (json['commands'] as List<dynamic>? ?? []);
    return commands
        .map((e) => CommandState.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CommandState> fetchCommand(String commandId) async {
    final json = await _get('/commands/$commandId');
    return CommandState.fromJson(json);
  }

  Future<TelemetrySnapshot> fetchLatestTelemetry(String deviceId) async {
    final json = await _get('/devices/$deviceId/telemetry/latest');
    return TelemetrySnapshot.fromJson(json);
  }

  Future<List<TelemetryPoint>> fetchTelemetryHistory(String deviceId,
      {required String from, required String to}) async {
    final json = await _get(
        '/devices/$deviceId/telemetry/history?from=$from&to=$to&bucket=hour');
    final points = (json['points'] as List<dynamic>? ?? []);
    return points
        .map((e) => TelemetryPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UpdateStatus>> fetchUpdates(String deviceId) async {
    final json = await _get('/devices/$deviceId/updates');
    final list = (json['updates'] as List<dynamic>? ?? []);
    return list
        .map((e) => UpdateStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UpdateStatus> fetchUpdate(String deviceId, String releaseId) async {
    final json = await _get('/devices/$deviceId/updates/$releaseId');
    return UpdateStatus.fromJson(json);
  }

  Future<List<AlertItem>> fetchAlerts({String? severity}) async {
    final query = severity != null ? '?severity=$severity' : '';
    final json = await _get('/alerts$query');
    final list = (json['alerts'] as List<dynamic>? ?? []);
    return list
        .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> acknowledgeAlert(String alertId) async {
    await _post('/alerts/$alertId/ack', {});
  }

  String get apiBaseUrl => Environment.apiBaseUrl;
}
