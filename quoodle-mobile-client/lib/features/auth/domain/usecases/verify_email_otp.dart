import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class VerifyEmailOtp {
  const VerifyEmailOtp(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call({
    required String email,
    required String challengeId,
    required String otpCode,
  }) {
    return _repository.verifyEmailOtp(
      email: email,
      challengeId: challengeId,
      otpCode: otpCode,
    );
  }
}
