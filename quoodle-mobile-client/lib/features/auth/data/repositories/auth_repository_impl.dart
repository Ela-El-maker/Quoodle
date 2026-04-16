import 'package:dio/dio.dart';
import 'package:secure_device_control/app/bootstrap/env.dart';
import 'package:secure_device_control/core/errors/failure_mapper.dart';
import 'package:secure_device_control/core/errors/failures.dart';
import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:secure_device_control/features/auth/data/services/google_auth_service.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/entities/email_otp_challenge.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(
    this._localDataSource,
    this._remoteDataSource,
    this._googleAuthService,
  );

  final AuthLocalDataSource _localDataSource;
  final AuthRemoteDataSource _remoteDataSource;
  final GoogleAuthService _googleAuthService;

  @override
  Future<Result<EmailOtpChallenge>> requestEmailOtp({
    required String email,
  }) async {
    try {
      final challenge = await _remoteDataSource.requestEmailOtp(
        email: email.trim(),
      );

      return Success<EmailOtpChallenge>(
        EmailOtpChallenge(
          challengeId: challenge.challengeId,
          resendAfterSeconds: challenge.resendAfterSeconds,
        ),
      );
    } on Object catch (error) {
      return FailureResult<EmailOtpChallenge>(_mapFailure(error));
    }
  }

  @override
  Future<Result<AuthUser>> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String otpCode,
  }) async {
    try {
      final fingerprint = await _localDataSource.getOrCreateDeviceFingerprint();
      final session = await _remoteDataSource.verifyEmailOtp(
        email: email.trim(),
        challengeId: challengeId.trim(),
        otpCode: otpCode.trim(),
        deviceFingerprint: fingerprint,
      );

      await _localDataSource.persistSessionTokens(
        token: session.jwt,
        refreshToken: session.refreshToken,
        sessionId: session.sessionId,
        userId: session.userId,
        userRole: session.userRole,
      );

      final profile = await _remoteDataSource.getProfile();
      await _localDataSource.persistUserProfile(
        email: profile.email,
        displayName: profile.displayName,
        userId: profile.userId,
        userRole: profile.userRole,
      );

      return Success<AuthUser>(_toAuthUser(profile));
    } on Object catch (error) {
      return FailureResult<AuthUser>(_mapFailure(error));
    }
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    try {
      final googlePayload = await _googleAuthService.requestAuthCode();
      final fingerprint = await _localDataSource.getOrCreateDeviceFingerprint();
      final session = await _remoteDataSource.exchangeGoogleCode(
        code: googlePayload.code,
        redirectUri: googlePayload.redirectUri,
        deviceFingerprint: fingerprint,
      );

      await _localDataSource.persistSessionTokens(
        token: session.jwt,
        refreshToken: session.refreshToken,
        sessionId: session.sessionId,
        userId: session.userId,
        userRole: session.userRole,
      );

      final profile = await _remoteDataSource.getProfile();
      await _localDataSource.persistUserProfile(
        email: profile.email,
        displayName: profile.displayName,
        userId: profile.userId,
        userRole: profile.userRole,
      );

      return Success<AuthUser>(_toAuthUser(profile));
    } on Object catch (error) {
      return FailureResult<AuthUser>(_mapFailure(error));
    }
  }

  @override
  Future<Result<void>> logout() async {
    try {
      final sessionId = await _localDataSource.getSessionId();
      if (sessionId != null && sessionId.isNotEmpty) {
        await _remoteDataSource.logout(sessionId: sessionId, allDevices: false);
      }
    } on Object {
      // Best-effort remote logout. We still clear local session below.
    }

    await _googleAuthService.clearCachedSession();
    await _localDataSource.clearSession();
    return const Success<void>(null);
  }

  @override
  Future<Result<AuthUser?>> getCurrentUser() async {
    final isAuthenticated = await _localDataSource.isAuthenticated();
    if (!isAuthenticated) {
      return const Success<AuthUser?>(null);
    }

    final userId = await _localDataSource.getUserId();
    final email = await _localDataSource.getUserEmail();
    final displayName = await _localDataSource.getDisplayName();
    final userRole = await _localDataSource.getUserRole();
    if (userId == null ||
        userId.isEmpty ||
        email == null ||
        email.isEmpty ||
        displayName == null ||
        displayName.isEmpty) {
      return const Success<AuthUser?>(null);
    }

    return Success<AuthUser?>(
      AuthUser(
        id: userId,
        email: email,
        displayName: displayName,
        role: (userRole == null || userRole.isEmpty) ? 'viewer' : userRole,
        twoFactorEnabled: false,
      ),
    );
  }

  @override
  Future<Result<AuthUser?>> restoreSession() async {
    final isAuthenticated = await _localDataSource.isAuthenticated();
    if (!isAuthenticated) {
      return const Success<AuthUser?>(null);
    }

    final refreshed = await refreshSession();
    if (refreshed is Success<AuthUser>) {
      return Success<AuthUser?>(refreshed.data);
    }

    final failure = (refreshed as FailureResult<AuthUser>).failure;
    if (failure is UnauthorizedFailure) {
      await _localDataSource.clearSession();
      return const Success<AuthUser?>(null);
    }
    return FailureResult<AuthUser?>(failure);
  }

  @override
  Future<Result<AuthUser>> refreshSession() async {
    try {
      final refreshToken = await _localDataSource.getRefreshToken();
      final existingSessionId = await _localDataSource.getSessionId();
      final existingUserId = await _localDataSource.getUserId();
      final existingUserRole = await _localDataSource.getUserRole();

      if (refreshToken == null || refreshToken.isEmpty) {
        return const FailureResult<AuthUser>(UnauthorizedFailure());
      }

      final refreshed = await _remoteDataSource.refreshSession(
        refreshToken: refreshToken,
      );
      await _localDataSource.persistSessionTokens(
        token: refreshed.jwt,
        refreshToken: refreshed.refreshToken,
        sessionId: existingSessionId,
        userId: existingUserId,
        userRole: existingUserRole,
      );

      final profile = await _remoteDataSource.getProfile();
      await _localDataSource.persistUserProfile(
        email: profile.email,
        displayName: profile.displayName,
        userId: profile.userId,
        userRole: profile.userRole,
      );

      return Success<AuthUser>(_toAuthUser(profile));
    } on Object catch (error) {
      return FailureResult<AuthUser>(_mapFailure(error));
    }
  }

  AuthUser _toAuthUser(UserProfilePayload profile) {
    return AuthUser(
      id: profile.userId,
      email: profile.email,
      displayName: profile.displayName,
      role: profile.userRole,
      twoFactorEnabled: profile.twoFactorEnabled,
    );
  }

  Failure _mapFailure(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final serverMessage = _extractServerMessage(error);
      final serverDetail = _extractServerDetailMessage(error);

      if (_isNetworkReachabilityIssue(error)) {
        return NetworkFailure(
          'Cannot reach control API at ${AppEnv.controlPlaneBaseUrl}. '
          'Set --dart-define=QDO_CONTROL_PLANE_BASE_URL=http://<your-pc-lan-ip>:8088/api '
          'when running on a physical phone.',
        );
      }

      if (serverDetail != null &&
          serverDetail.isNotEmpty &&
          statusCode != null &&
          statusCode >= 400 &&
          statusCode < 500) {
        return ValidationFailure(serverDetail);
      }

      if (serverMessage == 'invalid_otp') {
        return const ValidationFailure('Invalid code. Please try again.');
      }
      if (serverMessage == 'rate_limited' || statusCode == 429) {
        return const RateLimitedFailure();
      }
      if (serverMessage == 'validation_error') {
        final detail = _extractValidationDetail(error);
        return ValidationFailure(
          detail ?? 'Invalid request. Please review your input and try again.',
        );
      }
      if (serverMessage == 'access_denied') {
        return const ForbiddenFailure(
          'Your account is not provisioned for Quoodle access.',
        );
      }
      if (serverMessage == 'google_auth_not_configured') {
        return const ValidationFailure(
          'Google sign-in is not configured on the control plane.',
        );
      }
      if (serverMessage == 'invalid_google_code') {
        return const ValidationFailure(
          'Google sign-in failed (OAuth code mismatch). Verify redirect URI and client configuration.',
        );
      }
      if (serverMessage == 'invalid_google_userinfo') {
        return const ValidationFailure(
          'Google sign-in failed while reading account profile.',
        );
      }
      if (serverMessage == 'google_email_not_verified') {
        return const ValidationFailure(
          'Your Google account email is not verified.',
        );
      }
      if (serverMessage == 'invalid_refresh') {
        return const UnauthorizedFailure();
      }
    }

    return FailureMapper.fromObject(error);
  }

  bool _isNetworkReachabilityIssue(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  String? _extractServerMessage(DioException error) {
    final body = error.response?.data;
    if (body is Map) {
      final message = body['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  String? _extractValidationDetail(DioException error) {
    final body = error.response?.data;
    if (body is! Map) {
      return null;
    }

    final errors = body['errors'];
    if (errors is! Map) {
      return null;
    }

    for (final entry in errors.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractServerDetailMessage(DioException error) {
    final body = error.response?.data;
    if (body is! Map) {
      return null;
    }

    final direct = body['error'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final message = body['message'];
    if (message is String &&
        message.trim().isNotEmpty &&
        !message.contains('_')) {
      return message.trim();
    }

    final errors = body['errors'];
    if (errors is Map) {
      for (final entry in errors.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is String && first.trim().isNotEmpty) {
            return first.trim();
          }
        }
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return null;
  }
}
