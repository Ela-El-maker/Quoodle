import 'package:google_sign_in/google_sign_in.dart';
import 'package:secure_device_control/core/errors/exceptions.dart';

class GoogleAuthCodePayload {
  const GoogleAuthCodePayload({
    required this.code,
    required this.redirectUri,
  });

  final String code;
  final String redirectUri;
}

abstract class GoogleAuthService {
  Future<GoogleAuthCodePayload> requestAuthCode();
  Future<void> clearCachedSession();
}

class GoogleSignInAuthService implements GoogleAuthService {
  GoogleSignInAuthService({
    required String serverClientId,
    required String redirectUri,
  })  : _serverClientId = serverClientId.trim(),
        _redirectUri = redirectUri.trim(),
        _googleSignIn = GoogleSignIn(
          scopes: const <String>['openid', 'email', 'profile'],
          serverClientId:
              serverClientId.trim().isEmpty ? null : serverClientId.trim(),
          forceCodeForRefreshToken: true,
        );

  final String _serverClientId;
  final String _redirectUri;
  final GoogleSignIn _googleSignIn;

  @override
  Future<GoogleAuthCodePayload> requestAuthCode() async {
    if (_serverClientId.isEmpty) {
      throw const ValidationException(
        'Google sign-in is not configured. Missing server client ID.',
      );
    }
    if (_redirectUri.isEmpty) {
      throw const ValidationException(
        'Google sign-in is not configured. Missing redirect URI.',
      );
    }

    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw const CancelledException('Google sign-in cancelled');
    }

    final code = account.serverAuthCode;
    if (code == null || code.isEmpty) {
      throw const ValidationException(
        'Google sign-in did not return an authorization code.',
      );
    }

    return GoogleAuthCodePayload(code: code, redirectUri: _redirectUri);
  }

  @override
  Future<void> clearCachedSession() async {
    await _googleSignIn.signOut();
  }
}
