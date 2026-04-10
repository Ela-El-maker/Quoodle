import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/core/errors/failures.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_providers.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

class AuthController extends Notifier<AuthSessionState> {
  @override
  AuthSessionState build() {
    Future<void>.microtask(restoreSession);
    return AuthSessionState.initial();
  }

  Future<void> restoreSession() async {
    state =
        state.copyWith(status: AuthSessionStatus.refreshing, clearError: true);

    final result = await ref.read(restoreSessionProvider).call();
    state = result.when(
      success: (user) => user == null
          ? const AuthSessionState(status: AuthSessionStatus.unauthenticated)
          : AuthSessionState(
              status: AuthSessionStatus.authenticated, user: user),
      failure: (failure) => AuthSessionState(
        status: AuthSessionStatus.error,
        errorMessage: failure.userMessage,
      ),
    );
  }

  Future<void> login({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    state = state.copyWith(
      status: AuthSessionStatus.authenticating,
      clearError: true,
      pendingEmail: email,
      pendingPassword: password,
    );

    final result = await ref.read(loginUserProvider).call(
          email: email,
          password: password,
          otpCode: otpCode,
        );

    state = result.when(
      success: (user) => AuthSessionState(
        status: AuthSessionStatus.authenticated,
        user: user,
      ),
      failure: (failure) {
        if (failure is TwoFactorRequiredFailure) {
          return state.copyWith(
            status: AuthSessionStatus.twoFactorRequired,
            clearError: true,
          );
        }

        return state.copyWith(
          status: AuthSessionStatus.error,
          errorMessage: failure.userMessage,
        );
      },
    );
  }

  Future<void> verifyTwoFactor(String otpCode) async {
    final email = state.pendingEmail;
    final password = state.pendingPassword;
    if (email == null || password == null) {
      state = state.copyWith(
        status: AuthSessionStatus.error,
        errorMessage: 'Login session expired. Please enter credentials again.',
      );
      return;
    }

    await login(email: email, password: password, otpCode: otpCode);
  }

  Future<void> logout() async {
    await ref.read(logoutUserProvider).call();
    state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
  }
}
