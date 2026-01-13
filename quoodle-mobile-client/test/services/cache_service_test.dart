import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/services/cache_service.dart';

void main() {
  group('CacheEntry', () {
    test('isExpired returns false when not expired', () {
      final entry = CacheEntry<String>(
        data: 'test',
        cachedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(entry.isExpired, isFalse);
    });

    test('isExpired returns true when expired', () {
      final entry = CacheEntry<String>(
        data: 'test',
        cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(entry.isExpired, isTrue);
    });

    test('age returns correct duration', () {
      final cachedAt = DateTime.now().subtract(const Duration(minutes: 5));
      final entry = CacheEntry<String>(
        data: 'test',
        cachedAt: cachedAt,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(entry.age.inMinutes, greaterThanOrEqualTo(5));
      expect(entry.age.inMinutes, lessThan(6));
    });

    test('toJson serializes correctly', () {
      final cachedAt = DateTime(2024, 1, 15, 10, 30);
      final expiresAt = DateTime(2024, 1, 15, 11, 30);
      final entry = CacheEntry<Map<String, dynamic>>(
        data: {'key': 'value'},
        cachedAt: cachedAt,
        expiresAt: expiresAt,
      );

      final json = entry.toJson((d) => d);

      expect(json['data'], {'key': 'value'});
      expect(json['cached_at'], cachedAt.toIso8601String());
      expect(json['expires_at'], expiresAt.toIso8601String());
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'data': 'test-data',
        'cached_at': '2024-01-15T10:30:00.000',
        'expires_at': '2024-01-15T11:30:00.000',
      };

      final entry = CacheEntry<String>.fromJson(
        json,
        (d) => d as String,
      );

      expect(entry.data, 'test-data');
      expect(entry.cachedAt.year, 2024);
      expect(entry.cachedAt.month, 1);
      expect(entry.cachedAt.day, 15);
    });
  });

  group('CacheResult', () {
    test('fresh creates non-cached result', () {
      final result = CacheResult<String>.fresh('data');

      expect(result.data, 'data');
      expect(result.fromCache, isFalse);
      expect(result.cachedAt, isNull);
      expect(result.isStale, isFalse);
    });

    test('cached creates cached result', () {
      final cachedAt = DateTime.now();
      final result = CacheResult<String>.cached('data', cachedAt);

      expect(result.data, 'data');
      expect(result.fromCache, isTrue);
      expect(result.cachedAt, cachedAt);
      expect(result.isStale, isFalse);
    });

    test('cached with isStale flag', () {
      final result = CacheResult<String>.cached(
        'data',
        DateTime.now(),
        isStale: true,
      );

      expect(result.fromCache, isTrue);
      expect(result.isStale, isTrue);
    });
  });

  group('CacheConfig', () {
    test('default config has sensible values', () {
      const config = CacheConfig();

      expect(config.defaultTtl, const Duration(minutes: 15));
      expect(config.devicesTtl, const Duration(minutes: 5));
      expect(config.alertsTtl, const Duration(minutes: 2));
      expect(config.telemetryTtl, const Duration(minutes: 1));
      expect(config.commandsTtl, const Duration(minutes: 5));
      expect(config.staleWhileRevalidate, isTrue);
    });

    test('custom config overrides defaults', () {
      const config = CacheConfig(
        defaultTtl: Duration(minutes: 30),
        devicesTtl: Duration(minutes: 10),
        staleWhileRevalidate: false,
      );

      expect(config.defaultTtl, const Duration(minutes: 30));
      expect(config.devicesTtl, const Duration(minutes: 10));
      expect(config.staleWhileRevalidate, isFalse);
    });
  });

  group('CacheKeys', () {
    test('devices key is correct', () {
      expect(CacheKeys.devices, 'cache.devices');
    });

    test('alerts key is correct', () {
      expect(CacheKeys.alerts, 'cache.alerts');
    });

    test('telemetry key generates correctly', () {
      expect(CacheKeys.telemetry('device-123'), 'cache.telemetry.device-123');
    });

    test('commands key generates correctly', () {
      expect(CacheKeys.commands('device-456'), 'cache.commands.device-456');
    });

    test('lastSync key is correct', () {
      expect(CacheKeys.lastSync, 'cache.last_sync');
    });
  });

  group('CacheService', () {
    test('getTtlFor returns correct TTL for each key type', () {
      final cache = CacheService();

      expect(cache.getTtlFor(CacheKeys.devices), const Duration(minutes: 5));
      expect(cache.getTtlFor(CacheKeys.alerts), const Duration(minutes: 2));
      expect(cache.getTtlFor(CacheKeys.telemetry('dev1')),
          const Duration(minutes: 1));
      expect(cache.getTtlFor(CacheKeys.commands('dev1')),
          const Duration(minutes: 5));
      expect(cache.getTtlFor('unknown.key'), const Duration(minutes: 15));
    });

    test('custom config affects TTL', () {
      final cache = CacheService(
        config: const CacheConfig(
          devicesTtl: Duration(minutes: 20),
          defaultTtl: Duration(hours: 1),
        ),
      );

      expect(cache.getTtlFor(CacheKeys.devices), const Duration(minutes: 20));
      expect(cache.getTtlFor('custom.key'), const Duration(hours: 1));
    });
  });
}
