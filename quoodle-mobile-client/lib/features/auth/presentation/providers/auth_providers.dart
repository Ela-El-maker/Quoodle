import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/bootstrap/env.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:secure_device_control/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:secure_device_control/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:secure_device_control/features/auth/data/services/google_auth_service.dart';
import 'package:secure_device_control/features/auth/domain/repositories/auth_repository.dart';
import 'package:secure_device_control/features/auth/domain/usecases/get_current_user.dart';
import 'package:secure_device_control/features/auth/domain/usecases/logout_user.dart';
import 'package:secure_device_control/features/auth/domain/usecases/refresh_session.dart';
import 'package:secure_device_control/features/auth/domain/usecases/request_email_otp.dart';
import 'package:secure_device_control/features/auth/domain/usecases/restore_session.dart';
import 'package:secure_device_control/features/auth/domain/usecases/sign_in_with_google.dart';
import 'package:secure_device_control/features/auth/domain/usecases/verify_email_otp.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_controller.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSource(
    ref.read(secureStorageServiceProvider),
    ref.read(keyValueStorageProvider),
  );
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.read(apiClientProvider));
});

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleSignInAuthService(
    serverClientId: AppEnv.googleServerClientId.trim(),
    redirectUri: AppEnv.googleRedirectUri.trim(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    ref.read(authLocalDataSourceProvider),
    ref.read(authRemoteDataSourceProvider),
    ref.read(googleAuthServiceProvider),
  );
});

final requestEmailOtpProvider = Provider<RequestEmailOtp>((ref) {
  return RequestEmailOtp(ref.read(authRepositoryProvider));
});

final verifyEmailOtpProvider = Provider<VerifyEmailOtp>((ref) {
  return VerifyEmailOtp(ref.read(authRepositoryProvider));
});

final signInWithGoogleProvider = Provider<SignInWithGoogle>((ref) {
  return SignInWithGoogle(ref.read(authRepositoryProvider));
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
