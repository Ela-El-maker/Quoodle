import 'dart:async';
import 'dart:io';

import '../models/alert.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../models/telemetry.dart';
import 'api_service.dart';
import 'cache_service.dart';

/// Network connectivity status.
enum ConnectivityStatus {
  online,
  offline,
  unknown,
}

/// Repository that provides offline support via caching.
///
/// This wraps [ApiService] and adds:
/// - Automatic caching of responses
/// - Offline fallback to cached data
/// - Stale-while-revalidate pattern
/// - Connectivity monitoring
class OfflineRepository {
  OfflineRepository({
    required ApiService api,
    CacheService? cache,
  })  : _api = api,
        _cache = cache ?? CacheService();

  final ApiService _api;
  final CacheService _cache;

  final _connectivityController =
      StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _lastKnownStatus = ConnectivityStatus.unknown;

  /// Stream of connectivity status changes.
  Stream<ConnectivityStatus> get connectivityStream =>
      _connectivityController.stream;

  /// Current connectivity status.
  ConnectivityStatus get connectivityStatus => _lastKnownStatus;

  /// Whether the device is currently online.
  bool get isOnline => _lastKnownStatus == ConnectivityStatus.online;

  /// Check current network connectivity.
  Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      _updateConnectivity(
          isOnline ? ConnectivityStatus.online : ConnectivityStatus.offline);
      return isOnline;
    } on SocketException catch (_) {
      _updateConnectivity(ConnectivityStatus.offline);
      return false;
    } on TimeoutException catch (_) {
      _updateConnectivity(ConnectivityStatus.offline);
      return false;
    }
  }

  void _updateConnectivity(ConnectivityStatus status) {
    if (_lastKnownStatus != status) {
      _lastKnownStatus = status;
      if (!_connectivityController.isClosed) {
        _connectivityController.add(status);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Devices
  // ─────────────────────────────────────────────────────────────────

  /// Fetch devices with offline fallback.
  Future<CacheResult<List<Device>>> fetchDevices(
      {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.devices;

    // Try cache first if not forcing refresh
    if (!forceRefresh) {
      final cached = await _cache.getValid<List<Device>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => Device.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null && !cached.isExpired) {
        return CacheResult.cached(cached.data, cached.cachedAt);
      }
    }

    // Try network
    try {
      final devices = await _api.fetchDevices();
      _updateConnectivity(ConnectivityStatus.online);

      // Cache the response
      await _cache.set<List<Device>>(
        cacheKey,
        devices,
        (d) => d.map((e) => e.toJson()).toList(),
        ttl: _cache.getTtlFor(cacheKey),
      );
      await _cache.recordSync();

      return CacheResult.fresh(devices);
    } catch (e) {
      _updateConnectivity(ConnectivityStatus.offline);

      // Return stale cache if available
      final stale = await _cache.get<List<Device>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => Device.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (stale != null) {
        return CacheResult.cached(stale.data, stale.cachedAt, isStale: true);
      }

      rethrow;
    }
  }

  /// Fetch a single device with offline fallback.
  Future<CacheResult<Device>> fetchDevice(String deviceId,
      {bool forceRefresh = false}) async {
    // Check devices cache first
    final devicesResult = await fetchDevices(forceRefresh: forceRefresh);
    final device = devicesResult.data.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => throw Exception('Device not found: $deviceId'),
    );
    return CacheResult(
      data: device,
      fromCache: devicesResult.fromCache,
      cachedAt: devicesResult.cachedAt,
      isStale: devicesResult.isStale,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Alerts
  // ─────────────────────────────────────────────────────────────────

  /// Fetch alerts with offline fallback.
  Future<CacheResult<List<AlertItem>>> fetchAlerts({
    String? severity,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheKeys.alerts;

    if (!forceRefresh) {
      final cached = await _cache.getValid<List<AlertItem>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null && !cached.isExpired) {
        var alerts = cached.data;
        if (severity != null) {
          alerts = alerts.where((a) => a.severity == severity).toList();
        }
        return CacheResult.cached(alerts, cached.cachedAt);
      }
    }

    try {
      final alerts = await _api.fetchAlerts(severity: severity);
      _updateConnectivity(ConnectivityStatus.online);

      // Cache all alerts (without filter)
      if (severity == null) {
        await _cache.set<List<AlertItem>>(
          cacheKey,
          alerts,
          (d) => d.map((e) => e.toJson()).toList(),
          ttl: _cache.getTtlFor(cacheKey),
        );
      }

      return CacheResult.fresh(alerts);
    } catch (e) {
      _updateConnectivity(ConnectivityStatus.offline);

      final stale = await _cache.get<List<AlertItem>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (stale != null) {
        var alerts = stale.data;
        if (severity != null) {
          alerts = alerts.where((a) => a.severity == severity).toList();
        }
        return CacheResult.cached(alerts, stale.cachedAt, isStale: true);
      }

      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Telemetry
  // ─────────────────────────────────────────────────────────────────

  /// Fetch latest telemetry for a device with offline fallback.
  Future<CacheResult<TelemetrySnapshot>> fetchLatestTelemetry(
    String deviceId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheKeys.telemetry(deviceId);

    if (!forceRefresh) {
      final cached = await _cache.getValid<TelemetrySnapshot>(
        cacheKey,
        (data) => TelemetrySnapshot.fromJson(data as Map<String, dynamic>),
      );
      if (cached != null && !cached.isExpired) {
        return CacheResult.cached(cached.data, cached.cachedAt);
      }
    }

    try {
      final telemetry = await _api.fetchLatestTelemetry(deviceId);
      _updateConnectivity(ConnectivityStatus.online);

      await _cache.set<TelemetrySnapshot>(
        cacheKey,
        telemetry,
        (d) => d.toJson(),
        ttl: _cache.getTtlFor(cacheKey),
      );

      return CacheResult.fresh(telemetry);
    } catch (e) {
      _updateConnectivity(ConnectivityStatus.offline);

      final stale = await _cache.get<TelemetrySnapshot>(
        cacheKey,
        (data) => TelemetrySnapshot.fromJson(data as Map<String, dynamic>),
      );
      if (stale != null) {
        return CacheResult.cached(stale.data, stale.cachedAt, isStale: true);
      }

      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Commands
  // ─────────────────────────────────────────────────────────────────

  /// Fetch command history for a device with offline fallback.
  Future<CacheResult<List<CommandState>>> fetchCommands(
    String deviceId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheKeys.commands(deviceId);

    if (!forceRefresh) {
      final cached = await _cache.getValid<List<CommandState>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => CommandState.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached != null && !cached.isExpired) {
        return CacheResult.cached(cached.data, cached.cachedAt);
      }
    }

    try {
      final commands = await _api.fetchDeviceCommands(deviceId);
      _updateConnectivity(ConnectivityStatus.online);

      await _cache.set<List<CommandState>>(
        cacheKey,
        commands,
        (d) => d.map((e) => e.toJson()).toList(),
        ttl: _cache.getTtlFor(cacheKey),
      );

      return CacheResult.fresh(commands);
    } catch (e) {
      _updateConnectivity(ConnectivityStatus.offline);

      final stale = await _cache.get<List<CommandState>>(
        cacheKey,
        (data) => (data as List)
            .map((e) => CommandState.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (stale != null) {
        return CacheResult.cached(stale.data, stale.cachedAt, isStale: true);
      }

      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Cache Management
  // ─────────────────────────────────────────────────────────────────

  /// Get the last sync timestamp.
  Future<DateTime?> getLastSync() => _cache.getLastSync();

  /// Clear all cached data.
  Future<void> clearCache() => _cache.clear();

  /// Invalidate cache for a specific device.
  Future<void> invalidateDevice(String deviceId) async {
    await _cache.remove(CacheKeys.telemetry(deviceId));
    await _cache.remove(CacheKeys.commands(deviceId));
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _connectivityController.close();
  }
}
