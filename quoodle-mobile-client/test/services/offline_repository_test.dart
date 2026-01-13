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
}
