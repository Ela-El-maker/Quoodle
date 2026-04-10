import 'package:secure_device_control/core/errors/failures.dart';
import 'package:secure_device_control/core/errors/result.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._localDataSource);

  final AuthLocalDataSource _localDataSource;

  static const _demoEmail = 'operator@quoodle.io';
  static const _demoPassword = 'Qd0pS3cur3!';
  static const _demoOtp = '123456';

  @override
  Future<Result<AuthUser>> login({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (email.trim() != _demoEmail || password != _demoPassword) {
      return const FailureResult<AuthUser>(
        ValidationFailure(
            'Invalid credentials. Try: operator@quoodle.io / Qd0pS3cur3!'),
      );
    }

    if (otpCode == null || otpCode.isEmpty) {
      return const FailureResult<AuthUser>(TwoFactorRequiredFailure());
    }

    if (otpCode != _demoOtp) {
      return const FailureResult<AuthUser>(
        ValidationFailure('Invalid verification code. Try: 123456'),
      );
    }

    final user = AuthUser(
      id: 'operator-001',
      email: _demoEmail,
      displayName: 'Operator',
    );

    await _localDataSource.persistSession(
      token: 'demo-token',
      refreshToken: 'demo-refresh-token',
      email: user.email,
      displayName: user.displayName,
    );

    return Success<AuthUser>(user);
  }

  @override
  Future<Result<void>> logout() async {
    await _localDataSource.clearSession();
    return const Success<void>(null);
  }

  @override
  Future<Result<AuthUser?>> getCurrentUser() async {
    final isAuthenticated = await _localDataSource.isAuthenticated();
    if (!isAuthenticated) {
      return const Success<AuthUser?>(null);
    }

    final email = await _localDataSource.getUserEmail() ?? _demoEmail;
    final name = await _localDataSource.getDisplayName() ?? 'Operator';

    return Success<AuthUser?>(
      AuthUser(id: 'operator-001', email: email, displayName: name),
    );
  }

  @override
  Future<Result<AuthUser?>> restoreSession() => getCurrentUser();

  @override
  Future<Result<AuthUser>> refreshSession() async {
    final currentUser = await getCurrentUser();
    return currentUser.when(
      success: (user) {
        if (user == null) {
          return const FailureResult<AuthUser>(UnauthorizedFailure());
        }
        return Success<AuthUser>(user);
      },
      failure: (failure) => FailureResult<AuthUser>(failure),
    );
  }
}
