import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class LoginUser {
  const LoginUser(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call({
    required String email,
    required String password,
    String? otpCode,
  }) {
    return _repository.login(
        email: email, password: password, otpCode: otpCode);
  }
}
