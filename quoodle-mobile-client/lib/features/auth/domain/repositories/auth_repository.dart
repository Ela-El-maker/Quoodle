import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';

abstract class AuthRepository {
  Future<Result<AuthUser>> login({
    required String email,
    required String password,
    String? otpCode,
  });

  Future<Result<void>> logout();

  Future<Result<AuthUser?>> getCurrentUser();

  Future<Result<AuthUser?>> restoreSession();

  Future<Result<AuthUser>> refreshSession();
}
