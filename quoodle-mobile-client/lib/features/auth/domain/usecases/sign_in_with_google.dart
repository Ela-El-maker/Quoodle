import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class SignInWithGoogle {
  const SignInWithGoogle(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthUser>> call() => _repository.signInWithGoogle();
}
