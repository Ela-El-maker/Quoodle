import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:secure_device_control/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';
import 'package:secure_device_control/features/auth/domain/usecases/get_current_user.dart';
import 'package:secure_device_control/features/auth/domain/usecases/login_user.dart';
import 'package:secure_device_control/features/auth/domain/usecases/logout_user.dart';
import 'package:secure_device_control/features/auth/domain/usecases/refresh_session.dart';
import 'package:secure_device_control/features/auth/domain/usecases/restore_session.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_controller.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSource(
    ref.read(secureStorageServiceProvider),
    ref.read(keyValueStorageProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.read(authLocalDataSourceProvider));
});

final loginUserProvider = Provider<LoginUser>((ref) {
  return LoginUser(ref.read(authRepositoryProvider));
});

final logoutUserProvider = Provider<LogoutUser>((ref) {
  return LogoutUser(ref.read(authRepositoryProvider));
});

final getCurrentUserProvider = Provider<GetCurrentUser>((ref) {
  return GetCurrentUser(ref.read(authRepositoryProvider));
});

final restoreSessionProvider = Provider<RestoreSession>((ref) {
  return RestoreSession(ref.read(authRepositoryProvider));
});

final refreshSessionProvider = Provider<RefreshSession>((ref) {
  return RefreshSession(ref.read(authRepositoryProvider));
});

final authControllerProvider =
    NotifierProvider<AuthController, AuthSessionState>(AuthController.new);
