import 'dart:math' as math;

import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/endpoints.dart';
import 'package:secure_device_control/features/dashboard/domain/entities/dashboard_summary.dart';

class DashboardRemoteDataSource {
  const DashboardRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSummary> fetchSummary() async {
    final results = await Future.wait<Map<String, dynamic>>([
      _apiClient.get(Endpoints.telemetryFleetSummary),
      _apiClient.get(
        Endpoints.telemetryFleetTimeseries,
        queryParameters: const <String, dynamic>{
          'hours': 24,
          'bucket_minutes': 60,
        },
      ),
      _apiClient.get(
        Endpoints.telemetryActivity,
        queryParameters: const <String, dynamic>{'limit': 12},
      ),
      _fetchDevices(),
      _apiClient.get(
        Endpoints.alerts,
        queryParameters: const <String, dynamic>{'limit': 200},
      ),
    ]);

    final fleetSummary = results[0];
    final fleetTimeseries = results[1];
    final activity = results[2];
    final devicesResponse = results[3];
    final alertsResponse = results[4];

    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final devicesRaw = _asList(devicesResponse['devices']);
    final devices = devicesRaw
        .whereType<Map>()
        .map(_toStringDynamicMap)
        .toList(growable: false);
    final deviceNameById = <String, String>{
      for (final device in devices)
        _asString(device['device_id']): _asString(device['device_name']).isEmpty
            ? _asString(device['device_id'])
            : _asString(device['device_name']),
    };

    final fleet = _toStringDynamicMap(fleetSummary['fleet']);
    final risk = _toStringDynamicMap(fleetSummary['risk']);
    final alerts = _toStringDynamicMap(fleetSummary['alerts']);
    final commands = _toStringDynamicMap(fleetSummary['commands']);

    final totalDevices = _toInt(fleet['total_devices']) ?? devices.length;
    final onlineDevices = _toInt(fleet['online']) ??
        devices
            .where((d) => _asString(d['resolved_presence_state']) == 'online')
            .length;
    final staleDevices = _toInt(fleet['stale']) ??
        devices
            .where((d) => _asString(d['resolved_presence_state']) == 'stale')
            .length;
    final offlineDevices = _toInt(fleet['offline']) ??
        devices
            .where((d) => _asString(d['resolved_presence_state']) == 'offline')
            .length;
    final reconnectingDevices = _toInt(fleet['reconnecting']) ??
        devices
            .where((d) =>
                _asString(d['resolved_presence_state']) == 'reconnecting')
            .length;
    final computedOffline = staleDevices + offlineDevices + reconnectingDevices;

    final activeCommands = _toInt(commands['active_total']) ?? 0;
    final criticalAlertsFromSummary = _toInt(alerts['critical_total']) ?? 0;

    final alertsRaw = _asList(alertsResponse['alerts'])
        .whereType<Map>()
        .map(_toStringDynamicMap)
        .toList(growable: false);
    final unacknowledgedAlerts = alertsRaw
        .where((a) => (_toBool(a['acknowledged']) ?? false) == false)
        .toList(growable: false);
    final criticalAlertsComputed = unacknowledgedAlerts
        .where((a) => _asString(a['severity']) == 'critical')
        .length;
    final criticalAlerts = criticalAlertsFromSummary > 0
        ? criticalAlertsFromSummary
        : criticalAlertsComputed;

    final compliantDevices = devices
        .where((d) => _asString(d['resolved_compliance_status']) == 'compliant')
        .length;
    final policySyncedDevices = devices
        .where((d) => (_toBool(d['resolved_policy_in_sync']) ?? false) == true)
        .length;
    final denominator = totalDevices <= 0 ? 1 : totalDevices;
    final complianceRate = (compliantDevices / denominator) * 100;
    final policySyncRate = (policySyncedDevices / denominator) * 100;

    final driftDevices = _toInt(risk['compliance_drift_devices']) ??
        devices
            .where((d) =>
                _asString(d['resolved_compliance_status']) != 'compliant')
            .length;
    final itemsNeedingAttention = math.max(criticalAlerts, driftDevices);

    final healthPoints =
        _buildFleetHealthPoints(fleetTimeseries, onlineDevices, totalDevices);
    final atRisk = _buildAtRiskDevices(devices);
    final activities = _buildActivityFeed(activity, deviceNameById);

    return DashboardSummary(
      greeting: greeting,
      operatorName: 'Operator',
      lastUpdated:
          _formatRelativeTimestamp(_asString(fleetSummary['timestamp'])),
      itemsNeedingAttention: itemsNeedingAttention,
      totalDevices: totalDevices,
      onlineDevices: onlineDevices,
      offlineDevices: computedOffline,
      activeCommands: activeCommands,
      criticalAlerts: criticalAlerts,
      complianceRate: complianceRate,
      compliantDevices: compliantDevices,
      policySyncRate: policySyncRate,
      syncedPolicyDevices: policySyncedDevices,
      fleetHealthSeries: healthPoints,
      atRiskDevices: atRisk,
      recentActivities: activities,
    );
  }

  Future<Map<String, dynamic>> _fetchDevices() async {
    final devices = <Map<String, dynamic>>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await _apiClient.get(
        Endpoints.devices,
        queryParameters: <String, dynamic>{'page': page, 'per_page': 200},
      );

      final pageDevices = _asList(response['devices'])
          .whereType<Map>()
          .map(_toStringDynamicMap)
          .toList(growable: false);
      devices.addAll(pageDevices);

      final meta = _toStringDynamicMap(response['meta']);
      final currentPage = _toInt(meta['current_page']) ?? page;
      lastPage = _toInt(meta['last_page']) ?? currentPage;
      page = currentPage + 1;
    } while (page <= lastPage);

    return <String, dynamic>{'devices': devices};
  }

  List<DashboardHealthPoint> _buildFleetHealthPoints(
    Map<String, dynamic> timeseriesPayload,
    int onlineDevices,
    int totalDevices,
  ) {
    final pointsRaw = _asList(timeseriesPayload['points']);
    if (pointsRaw.isEmpty) {
      final fallback =
          totalDevices <= 0 ? 0.0 : (onlineDevices / totalDevices) * 100;
      return List<DashboardHealthPoint>.generate(
        24,
        (i) => DashboardHealthPoint(x: i.toDouble(), y: fallback),
      );
    }

    final points = <DashboardHealthPoint>[];
    var x = 0.0;
    for (final raw in pointsRaw) {
      if (raw is! Map) {
        continue;
      }
      final point = _toStringDynamicMap(raw);
      final avgRisk = _toDouble(point['avg_risk_score']) ?? 50;
      final health = (100 - avgRisk).clamp(0, 100).toDouble();
      points.add(DashboardHealthPoint(x: x, y: health));
      x += 1;
    }

    if (points.isEmpty) {
      return List<DashboardHealthPoint>.generate(
        24,
        (i) => DashboardHealthPoint(x: i.toDouble(), y: 0),
      );
    }
    return points;
  }

  List<DashboardAtRiskDevice> _buildAtRiskDevices(
      List<Map<String, dynamic>> devices) {
    final sorted = List<Map<String, dynamic>>.from(devices)
      ..sort((a, b) => (_toInt(b['risk_score']) ?? 0)
          .compareTo(_toInt(a['risk_score']) ?? 0));

    final candidates = sorted.where((device) {
      final risk = _toInt(device['risk_score']) ?? 0;
      final status = _asString(device['resolved_presence_state']);
      final compliance = _asString(device['resolved_compliance_status']);
      return risk >= 60 || status != 'online' || compliance != 'compliant';
    }).take(3);

    return candidates.map((device) {
      final status = _asString(device['resolved_presence_state']);
      final compliance = _asString(device['resolved_compliance_status']);
      final inSync = _toBool(device['resolved_policy_in_sync']) ?? true;
      final reason = switch (status) {
        'offline' => 'No heartbeat from device',
        'stale' => 'Device telemetry is stale',
        'reconnecting' => 'Device reconnecting',
        _ => compliance != 'compliant'
            ? 'Compliance drift detected'
            : (!inSync ? 'Policy drift detected' : 'Elevated risk score'),
      };

      return DashboardAtRiskDevice(
        id: _asString(device['device_id']),
        name: _asString(device['device_name']),
        status: status,
        reason: reason,
        riskScore: _toInt(device['risk_score']) ?? 0,
      );
    }).toList(growable: false);
  }

  List<DashboardActivityItem> _buildActivityFeed(
    Map<String, dynamic> activityPayload,
    Map<String, String> deviceNameById,
  ) {
    final events = _asList(activityPayload['events'])
        .whereType<Map>()
        .map(_toStringDynamicMap)
        .take(5);

    final items = <DashboardActivityItem>[];
    for (final event in events) {
      final eventType = _asString(event['event_type']);
      final detail = _toStringDynamicMap(event['detail']);
      final deviceId = _asString(event['device_id']);
      final deviceName = deviceNameById[deviceId] ?? deviceId;
      final timestamp = _formatTimeLabel(_asString(event['timestamp']));

      if (eventType == 'command') {
        final method = _asString(detail['method']).ifEmpty('command');
        items.add(
          DashboardActivityItem(
            commandMethod: method,
            commandLabel: _humanizeMethod(method),
            deviceId: deviceId,
            deviceName: deviceName,
            status: _asString(detail['state']).ifEmpty('queued'),
            timestampLabel: timestamp,
            initiator: 'Operator',
          ),
        );
        continue;
      }

      if (eventType == 'alert') {
        final severity = _asString(detail['severity']).ifEmpty('warning');
        items.add(
          DashboardActivityItem(
            commandMethod: 'alert',
            commandLabel: 'Alert',
            deviceId: deviceId,
            deviceName: deviceName,
            status: severity == 'critical' || severity == 'high'
                ? 'failed'
                : 'executing',
            timestampLabel: timestamp,
            initiator: 'System',
          ),
        );
        continue;
      }

      items.add(
        DashboardActivityItem(
          commandMethod: 'collect_telemetry',
          commandLabel: 'Telemetry',
          deviceId: deviceId,
          deviceName: deviceName,
          status: 'completed',
          timestampLabel: timestamp,
          initiator: 'System',
        ),
      );
    }

    return items;
  }

  String _humanizeMethod(String method) {
    return method
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _formatRelativeTimestamp(String isoTimestamp) {
    if (isoTimestamp.isEmpty) {
      return 'just now';
    }
    final parsed = DateTime.tryParse(isoTimestamp);
    if (parsed == null) {
      return 'just now';
    }
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _formatTimeLabel(String isoTimestamp) {
    final parsed = DateTime.tryParse(isoTimestamp);
    if (parsed == null) {
      return '--';
    }
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Map<String, dynamic> _toStringDynamicMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return const <String, dynamic>{};
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const <dynamic>[];
  }

  String _asString(Object? value) {
    if (value is String) {
      return value;
    }
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _toDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool? _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
