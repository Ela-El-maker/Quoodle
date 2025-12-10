import 'api_service.dart';

class AuthService {
  AuthService(this._api);

  final ApiService _api;

  Future<Map<String, dynamic>> login(String email, String password, {String? twoFactor}) {
    return _api.login(email: email, password: password, twoFactorCode: twoFactor, deviceFingerprint: 'mobile');
  }

  Future<Map<String, dynamic>> register(String displayName, String email, String password) {
    return _api.register(displayName: displayName, email: email, password: password, pubkey: 'mobile-pubkey');
  }
}
