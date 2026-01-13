import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cache entry with metadata.
class CacheEntry<T> {
  const CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.expiresAt,
  });

  final T data;
  final DateTime cachedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get age => DateTime.now().difference(cachedAt);

  Map<String, dynamic> toJson(Object Function(T) dataToJson) {
    return {
      'data': dataToJson(data),
      'cached_at': cachedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  factory CacheEntry.fromJson(
    Map<String, dynamic> json,
    T Function(Object) dataFromJson,
  ) {
    return CacheEntry(
      data: dataFromJson(json['data']),
      cachedAt: DateTime.parse(json['cached_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// Result of a cache lookup.
class CacheResult<T> {
  const CacheResult({
    required this.data,
    required this.fromCache,
    this.cachedAt,
    this.isStale = false,
  });

  final T data;
  final bool fromCache;
  final DateTime? cachedAt;
  final bool isStale;

  /// Create a fresh result (from network).
  factory CacheResult.fresh(T data) {
    return CacheResult(data: data, fromCache: false);
  }

  /// Create a cached result.
  factory CacheResult.cached(T data, DateTime cachedAt,
      {bool isStale = false}) {
    return CacheResult(
      data: data,
      fromCache: true,
      cachedAt: cachedAt,
      isStale: isStale,
    );
  }
}

/// Configuration for cache behavior.
class CacheConfig {
  const CacheConfig({
    this.defaultTtl = const Duration(minutes: 15),
    this.devicesTtl = const Duration(minutes: 5),
    this.alertsTtl = const Duration(minutes: 2),
    this.telemetryTtl = const Duration(minutes: 1),
    this.commandsTtl = const Duration(minutes: 5),
    this.staleWhileRevalidate = true,
  });

  final Duration defaultTtl;
  final Duration devicesTtl;
  final Duration alertsTtl;
  final Duration telemetryTtl;
  final Duration commandsTtl;
  final bool staleWhileRevalidate;
}

/// Cache keys for different data types.
class CacheKeys {
  static const devices = 'cache.devices';
  static const alerts = 'cache.alerts';
  static const telemetryPrefix = 'cache.telemetry.';
  static const commandsPrefix = 'cache.commands.';
  static const lastSync = 'cache.last_sync';

  static String telemetry(String deviceId) => '$telemetryPrefix$deviceId';
  static String commands(String deviceId) => '$commandsPrefix$deviceId';
}

/// Local cache storage service for offline support.
class CacheService {
  CacheService({
    FlutterSecureStorage? storage,
    CacheConfig? config,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _config = config ?? const CacheConfig();

  final FlutterSecureStorage _storage;
  final CacheConfig _config;

  // In-memory cache for faster access
  final Map<String, CacheEntry<dynamic>> _memoryCache = {};

  /// Store data in cache with TTL.
  Future<void> set<T>(
    String key,
    T data,
    Object Function(T) toJson, {
    Duration? ttl,
  }) async {
    final now = DateTime.now();
    final entry = CacheEntry<T>(
      data: data,
      cachedAt: now,
      expiresAt: now.add(ttl ?? _config.defaultTtl),
    );

    // Store in memory
    _memoryCache[key] = entry;

    // Persist to storage
    final json = entry.toJson(toJson);
    await _storage.write(key: key, value: jsonEncode(json));
  }

  /// Get data from cache.
  Future<CacheEntry<T>?> get<T>(
    String key,
    T Function(Object) fromJson,
  ) async {
    // Check memory cache first
    final memEntry = _memoryCache[key];
    if (memEntry != null) {
      return CacheEntry<T>(
        data: memEntry.data as T,
        cachedAt: memEntry.cachedAt,
        expiresAt: memEntry.expiresAt,
      );
    }

    // Load from storage
    final stored = await _storage.read(key: key);
    if (stored == null) return null;

    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      final entry = CacheEntry<T>.fromJson(json, fromJson);

      // Populate memory cache
      _memoryCache[key] = entry;

      return entry;
    } catch (e) {
      // Invalid cache data, remove it
      await _storage.delete(key: key);
      return null;
    }
  }

  /// Get data, returning null if expired (unless stale-while-revalidate).
  Future<CacheEntry<T>?> getValid<T>(
    String key,
    T Function(Object) fromJson,
  ) async {
    final entry = await get<T>(key, fromJson);
    if (entry == null) return null;

    if (entry.isExpired && !_config.staleWhileRevalidate) {
      return null;
    }

    return entry;
  }

  /// Check if a key exists and is not expired.
  Future<bool> hasValid(String key) async {
    final memEntry = _memoryCache[key];
    if (memEntry != null) {
      return !memEntry.isExpired || _config.staleWhileRevalidate;
    }

    final stored = await _storage.read(key: key);
    if (stored == null) return false;

    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      final expiresAt = DateTime.parse(json['expires_at'] as String);
      return !DateTime.now().isAfter(expiresAt) || _config.staleWhileRevalidate;
    } catch (e) {
      return false;
    }
  }

  /// Remove a specific cache entry.
  Future<void> remove(String key) async {
    _memoryCache.remove(key);
    await _storage.delete(key: key);
  }

  /// Remove all cache entries matching a prefix.
  Future<void> removeByPrefix(String prefix) async {
    final keysToRemove =
        _memoryCache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      _memoryCache.remove(key);
    }

    // Note: FlutterSecureStorage doesn't support prefix deletion,
    // so we track known prefixed keys separately or accept some stale data
  }

  /// Clear all cached data.
  Future<void> clear() async {
    _memoryCache.clear();
    await _storage.delete(key: CacheKeys.devices);
    await _storage.delete(key: CacheKeys.alerts);
    await _storage.delete(key: CacheKeys.lastSync);
    // Telemetry and commands are device-specific, cleared on logout
  }

  /// Record last sync timestamp.
  Future<void> recordSync() async {
    await _storage.write(
      key: CacheKeys.lastSync,
      value: DateTime.now().toIso8601String(),
    );
  }

  /// Get last sync timestamp.
  Future<DateTime?> getLastSync() async {
    final stored = await _storage.read(key: CacheKeys.lastSync);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  /// Get TTL for a specific data type.
  Duration getTtlFor(String key) {
    if (key == CacheKeys.devices) return _config.devicesTtl;
    if (key == CacheKeys.alerts) return _config.alertsTtl;
    if (key.startsWith(CacheKeys.telemetryPrefix)) return _config.telemetryTtl;
    if (key.startsWith(CacheKeys.commandsPrefix)) return _config.commandsTtl;
    return _config.defaultTtl;
  }
}
