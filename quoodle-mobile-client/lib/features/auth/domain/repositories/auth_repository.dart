import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/entities/email_otp_challenge.dart';

abstract class AuthRepository {
  Future<Result<EmailOtpChallenge>> requestEmailOtp({
    required String email,
  });

  Future<Result<AuthUser>> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String otpCode,
  });

  Future<Result<AuthUser>> signInWithGoogle();

  Future<Result<void>> logout();

  Future<Result<AuthUser?>> getCurrentUser();

  Future<Result<AuthUser?>> restoreSession();

  Future<Result<AuthUser>> refreshSession();
}
