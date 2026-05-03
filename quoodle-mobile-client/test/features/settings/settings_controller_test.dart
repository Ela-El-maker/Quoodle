import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/core/storage/key_value_storage.dart';
import 'package:secure_device_control/core/storage/secure_storage_service.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_controller.dart';

void main() {
  test('SettingsController hydrates and updates notification prefs', () async {
    final keyValueStorage = _InMemoryKeyValueStorage(
      bools: <String, bool>{
        StorageKeys.notifCriticalAlerts: true,
      },
    );
    final secureStorage = _InMemorySecureStorage(
      values: <String, String>{
        StorageKeys.sessionId: 'sess_test_current',
      },
    );

    final container = ProviderContainer(
      overrides: [
        keyValueStorageProvider.overrideWithValue(keyValueStorage),
        secureStorageServiceProvider.overrideWithValue(secureStorage),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(settingsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final hydratedState = container.read(settingsControllerProvider);
    expect(hydratedState.isLoading, isFalse);
    expect(hydratedState.sessions.length, 1);
    expect(hydratedState.sessions.first.id, 'sess_test_current');

    controller.setNotifCriticalAlerts(false);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(settingsControllerProvider).notifCriticalAlerts,
      isFalse,
    );
    expect(
      await keyValueStorage.getBool(StorageKeys.notifCriticalAlerts),
      isFalse,
    );
  });
}

class _InMemoryKeyValueStorage implements KeyValueStorage {
  _InMemoryKeyValueStorage({
    Map<String, String>? strings,
    Map<String, bool>? bools,
  })  : _strings = strings ?? <String, String>{},
        _bools = bools ?? <String, bool>{};

  final Map<String, String> _strings;
  final Map<String, bool> _bools;

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<bool?> getBool(String key) async => _bools[key];

  @override
  Future<void> remove(String key) async {
    _strings.remove(key);
    _bools.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _bools[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }
}

class _InMemorySecureStorage implements SecureStorageService {
  _InMemorySecureStorage({Map<String, String>? values})
      : _values = values ?? <String, String>{};

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
