import 'package:secure_device_control/core/storage/key_value_storage.dart';
import 'package:secure_device_control/core/storage/secure_storage_service.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';

class AuthLocalDataSource {
  const AuthLocalDataSource(this._secureStorage, this._keyValueStorage);

  final SecureStorageService _secureStorage;
  final KeyValueStorage _keyValueStorage;

  Future<void> persistSession({
    required String token,
    required String refreshToken,
    required String email,
    required String displayName,
  }) async {
    await _secureStorage.write(StorageKeys.authToken, token);
    await _secureStorage.write(StorageKeys.refreshToken, refreshToken);
    await _keyValueStorage.setBool(StorageKeys.isAuthenticated, true);
    await _keyValueStorage.setString(StorageKeys.userEmail, email);
    await _keyValueStorage.setString(StorageKeys.userName, displayName);
  }

  Future<bool> isAuthenticated() async {
    return (await _keyValueStorage.getBool(StorageKeys.isAuthenticated)) ??
        false;
  }

  Future<String?> getUserEmail() =>
      _keyValueStorage.getString(StorageKeys.userEmail);

  Future<String?> getDisplayName() =>
      _keyValueStorage.getString(StorageKeys.userName);

  Future<void> clearSession() async {
    await _secureStorage.delete(StorageKeys.authToken);
    await _secureStorage.delete(StorageKeys.refreshToken);
    await _keyValueStorage.remove(StorageKeys.isAuthenticated);
    await _keyValueStorage.remove(StorageKeys.userEmail);
    await _keyValueStorage.remove(StorageKeys.userName);
  }
}
