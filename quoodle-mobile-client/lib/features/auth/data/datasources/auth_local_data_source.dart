import 'dart:math';

import 'package:secure_device_control/core/storage/key_value_storage.dart';
import 'package:secure_device_control/core/storage/secure_storage_service.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';

class AuthLocalDataSource {
  const AuthLocalDataSource(this._secureStorage, this._keyValueStorage);

  final SecureStorageService _secureStorage;
  final KeyValueStorage _keyValueStorage;

  Future<void> persistSessionTokens({
    required String token,
    required String refreshToken,
    String? sessionId,
    String? userId,
    String? userRole,
  }) async {
    await _secureStorage.write(StorageKeys.authToken, token);
    await _secureStorage.write(StorageKeys.refreshToken, refreshToken);
    if (sessionId != null && sessionId.isNotEmpty) {
      await _secureStorage.write(StorageKeys.sessionId, sessionId);
    }
    if (userId != null && userId.isNotEmpty) {
      await _keyValueStorage.setString(StorageKeys.userId, userId);
    }
    if (userRole != null && userRole.isNotEmpty) {
      await _keyValueStorage.setString(StorageKeys.userRole, userRole);
    }
    await _keyValueStorage.setBool(StorageKeys.isAuthenticated, true);
  }

  Future<void> persistUserProfile({
    required String email,
    required String displayName,
    String? userId,
    String? userRole,
  }) async {
    await _keyValueStorage.setString(StorageKeys.userEmail, email);
    await _keyValueStorage.setString(StorageKeys.userName, displayName);
    if (userId != null && userId.isNotEmpty) {
      await _keyValueStorage.setString(StorageKeys.userId, userId);
    }
    if (userRole != null && userRole.isNotEmpty) {
      await _keyValueStorage.setString(StorageKeys.userRole, userRole);
    }
  }

  Future<bool> isAuthenticated() async {
    return (await _keyValueStorage.getBool(StorageKeys.isAuthenticated)) ??
        false;
  }

  Future<String?> getUserEmail() =>
      _keyValueStorage.getString(StorageKeys.userEmail);

  Future<String?> getDisplayName() =>
      _keyValueStorage.getString(StorageKeys.userName);

  Future<String?> getUserId() => _keyValueStorage.getString(StorageKeys.userId);

  Future<String?> getUserRole() =>
      _keyValueStorage.getString(StorageKeys.userRole);

  Future<String?> getRefreshToken() =>
      _secureStorage.read(StorageKeys.refreshToken);

  Future<String?> getSessionId() => _secureStorage.read(StorageKeys.sessionId);

  Future<String?> getAuthToken() => _secureStorage.read(StorageKeys.authToken);

  Future<String> getOrCreateDeviceFingerprint() async {
    final existing = await _secureStorage.read(StorageKeys.deviceFingerprint);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final fingerprint =
        'qoodle-mobile-${DateTime.now().millisecondsSinceEpoch}-$suffix';
    await _secureStorage.write(StorageKeys.deviceFingerprint, fingerprint);
    return fingerprint;
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(StorageKeys.authToken);
    await _secureStorage.delete(StorageKeys.refreshToken);
    await _secureStorage.delete(StorageKeys.sessionId);
    await _keyValueStorage.remove(StorageKeys.isAuthenticated);
    await _keyValueStorage.remove(StorageKeys.userId);
    await _keyValueStorage.remove(StorageKeys.userRole);
    await _keyValueStorage.remove(StorageKeys.userEmail);
    await _keyValueStorage.remove(StorageKeys.userName);
  }
}
