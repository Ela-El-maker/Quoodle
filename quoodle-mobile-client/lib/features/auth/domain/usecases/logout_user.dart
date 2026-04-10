import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class LogoutUser {
  const LogoutUser(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call() => _repository.logout();
}
