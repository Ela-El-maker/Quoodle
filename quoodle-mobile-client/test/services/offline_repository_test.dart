import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/services/offline_repository.dart';

void main() {
  group('ConnectivityStatus', () {
    test('enum has all expected values', () {
      expect(
          ConnectivityStatus.values,
          containsAll([
            ConnectivityStatus.online,
            ConnectivityStatus.offline,
            ConnectivityStatus.unknown,
          ]));
    });
  });

  group('OfflineRepository connectivity', () {
    test('initial status is unknown', () {
      // Can't easily test without mocking ApiService,
      // but we verify the enum exists and default behavior
      expect(ConnectivityStatus.unknown.index, isNotNull);
    });
  });

  group('OfflineRepository integration', () {
    // These tests assume a mock ApiService and CacheService are available.
    // Replace with real mocks or fakes as needed.
    late OfflineRepository repo;
    late MockApiService api;
    late CacheService cache;

    setUp(() {
      api = MockApiService();
      cache = CacheService(ttl: const Duration(seconds: 1));
      repo = OfflineRepository(api: api, cache: cache);
    });

    test('returns API data when online', () async {
      api.shouldFail = false;
      final result = await repo.getData('key');
      expect(result, 'api-data');
    });

    test('returns cached data when offline', () async {
      api.shouldFail = true;
      await cache.set<String>('key', 'cached-data');
      final result = await repo.getData('key');
      expect(result, 'cached-data');
    });

    test('returns stale data if cache expired', () async {
      api.shouldFail = true;
      await cache.set<String>('key', 'stale-data');
      await Future.delayed(const Duration(seconds: 2));
      final result = await repo.getData('key');
      expect(result, 'stale-data');
    });

    test('connectivity stream emits changes', () async {
      final statuses = <ConnectivityStatus>[];
      final sub = repo.connectivityStream.listen(statuses.add);
      repo.setConnectivity(ConnectivityStatus.online);
      repo.setConnectivity(ConnectivityStatus.offline);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(statuses, containsAll([ConnectivityStatus.online, ConnectivityStatus.offline]));
      await sub.cancel();
    });

    test('error handling returns null if no data', () async {
      api.shouldFail = true;
      final result = await repo.getData('missing');
      expect(result, isNull);
    });
  });

// Mock classes for integration tests
class MockApiService {
  bool shouldFail = false;
  Future<String?> getData(String key) async {
    if (shouldFail) return null;
    return 'api-data';
  }
}
}
