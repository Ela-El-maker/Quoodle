import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/email_otp_challenge.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class RequestEmailOtp {
  const RequestEmailOtp(this._repository);

  final AuthRepository _repository;

  Future<Result<EmailOtpChallenge>> call({required String email}) {
    return _repository.requestEmailOtp(email: email);
  }
}
