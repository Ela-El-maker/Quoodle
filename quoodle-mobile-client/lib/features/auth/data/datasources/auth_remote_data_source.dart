import 'package:dio/dio.dart';
import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/core/network/endpoints.dart';

class OtpChallengePayload {
  const OtpChallengePayload({
    required this.challengeId,
    required this.resendAfterSeconds,
  });

  final String challengeId;
  final int resendAfterSeconds;
}

class AuthSessionPayload {
  const AuthSessionPayload({
    required this.jwt,
    required this.refreshToken,
    required this.sessionId,
    required this.userId,
    required this.userRole,
  });

  final String jwt;
  final String refreshToken;
  final String sessionId;
  final String userId;
  final String userRole;
}

class RefreshSessionPayload {
  const RefreshSessionPayload({
    required this.jwt,
    required this.refreshToken,
  });

  final String jwt;
  final String refreshToken;
}

class UserProfilePayload {
  const UserProfilePayload({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.userRole,
    required this.twoFactorEnabled,
  });

  final String userId;
  final String email;
  final String displayName;
  final String userRole;
  final bool twoFactorEnabled;
}

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<OtpChallengePayload> requestEmailOtp({
    required String email,
  }) async {
    final response = await _apiClient.post(
      Endpoints.requestOtp,
      data: <String, dynamic>{'email': email},
    );

    return OtpChallengePayload(
      challengeId: _asString(response['challenge_id']),
      resendAfterSeconds: _asInt(response['resend_after_seconds']) ?? 60,
    );
  }

  Future<AuthSessionPayload> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String otpCode,
    required String deviceFingerprint,
    String? pushToken,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'challenge_id': challengeId,
      'otp': otpCode,
      'device_fingerprint': deviceFingerprint,
      if (pushToken != null && pushToken.isNotEmpty) 'push_token': pushToken,
    };

    final response = await _apiClient.post(Endpoints.verifyOtp, data: payload);
    return _parseSession(response);
  }

  Future<AuthSessionPayload> exchangeGoogleCode({
    required String code,
    required String redirectUri,
    required String deviceFingerprint,
    String? pushToken,
  }) async {
    final redirectCandidates = <String>[
      redirectUri.trim(),
      'http://localhost:3000/api/auth/google/callback',
      'http://127.0.0.1:3000/api/auth/google/callback',
    ].where((uri) => uri.isNotEmpty).toSet().toList(growable: false);

    DioException? lastRetryableError;
    for (final candidateRedirectUri in redirectCandidates) {
      final payload = <String, dynamic>{
        'code': code,
        'redirect_uri': candidateRedirectUri,
        'device_fingerprint': deviceFingerprint,
        if (pushToken != null && pushToken.isNotEmpty) 'push_token': pushToken,
      };

      try {
        final response = await _apiClient.post(
          Endpoints.exchangeGoogleCode,
          data: payload,
        );
        return _parseSession(response);
      } on DioException catch (error) {
        if (!_isRetryableGoogleCodeExchangeError(error)) {
          rethrow;
        }
        lastRetryableError = error;
      }
    }

    if (lastRetryableError != null) {
      throw lastRetryableError;
    }

    throw DioException(
      requestOptions: RequestOptions(path: Endpoints.exchangeGoogleCode),
      type: DioExceptionType.unknown,
      error: 'Google sign-in failed before request was sent.',
    );
  }

  Future<RefreshSessionPayload> refreshSession({
    required String refreshToken,
  }) async {
    final response = await _apiClient.post(
      Endpoints.refreshSession,
      data: <String, dynamic>{'refresh_token': refreshToken},
    );
    return RefreshSessionPayload(
      jwt: _asString(response['jwt']),
      refreshToken: _asString(response['refresh_token']),
    );
  }

  Future<UserProfilePayload> getProfile() async {
    final response = await _apiClient.get(Endpoints.profile);
    return UserProfilePayload(
      userId: _asString(response['user_id']),
      email: _asString(response['email']),
      displayName: _asString(response['display_name']),
      userRole: _asString(response['user_role']),
      twoFactorEnabled: _asBool(response['two_factor_enabled']),
    );
  }

  Future<void> logout({
    required String sessionId,
    required bool allDevices,
  }) async {
    await _apiClient.post(
      Endpoints.logout,
      data: <String, dynamic>{
        'session_id': sessionId,
        'all_devices': allDevices,
      },
    );
  }

  AuthSessionPayload _parseSession(Map<String, dynamic> response) {
    return AuthSessionPayload(
      jwt: _asString(response['jwt']),
      refreshToken: _asString(response['refresh_token']),
      sessionId: _asString(response['session_id']),
      userId: _asString(response['user_id']),
      userRole: _asString(response['user_role']),
    );
  }

  static String _asString(Object? value) {
    if (value is String) return value;
    if (value == null) return '';
    return value.toString();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  bool _isRetryableGoogleCodeExchangeError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != 401 && statusCode != 422) {
      return false;
    }

    final payload = error.response?.data;
    if (payload is! Map) {
      return false;
    }

    final message = _asString(payload['message']);
    if (message == 'invalid_google_code') {
      return true;
    }

    if (message == 'validation_error') {
      final errors = payload['errors'];
      if (errors is Map && errors.containsKey('redirect_uri')) {
        return true;
      }
    }
    return false;
  }
}
