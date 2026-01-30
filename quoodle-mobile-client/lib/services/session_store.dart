import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const _kJwt = 'auth.jwt';
  static const _kRefresh = 'auth.refresh';
  static const _kUserId = 'auth.user_id';
  static const _kSessionId = 'auth.session_id';
  static const _kUserRole = 'auth.user_role';

  static String? jwt;
  static String? refreshToken;
  static String? userId;
  static String? sessionId;
  static String? userRole;

  static bool get isLoggedIn => userId != null && sessionId != null;

  static Future<void> init() async {
    jwt = await _storage.read(key: _kJwt);
    refreshToken = await _storage.read(key: _kRefresh);
    userId = await _storage.read(key: _kUserId);
    sessionId = await _storage.read(key: _kSessionId);
    userRole = await _storage.read(key: _kUserRole);
  }

  static Future<void> setAuth({
    required String userId,
    required String sessionId,
    String? jwt,
    String? refreshToken,
    String? userRole,
  }) async {
    SessionStore.userId = userId;
    SessionStore.sessionId = sessionId;
    SessionStore.jwt = jwt;
    SessionStore.refreshToken = refreshToken;
    if (userRole != null) {
      SessionStore.userRole = userRole;
    }

    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kSessionId, value: sessionId);
    if (jwt != null) {
      await _storage.write(key: _kJwt, value: jwt);
    }
    if (refreshToken != null) {
      await _storage.write(key: _kRefresh, value: refreshToken);
    }
    if (userRole != null) {
      await _storage.write(key: _kUserRole, value: userRole);
    }
  }

  static Future<void> clear() async {
    jwt = null;
    refreshToken = null;
    userId = null;
    sessionId = null;
    userRole = null;
    await _storage.delete(key: _kJwt);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kSessionId);
    await _storage.delete(key: _kUserRole);
  }

  static Future<void> setRole(String role) async {
    userRole = role;
    await _storage.write(key: _kUserRole, value: role);
  }
}
