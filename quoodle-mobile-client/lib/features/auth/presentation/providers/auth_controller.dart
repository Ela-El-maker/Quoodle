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
        status: AuthSessionStatus.unauthenticated,
        errorMessage: failure.userMessage,
      ),
    );
  }

  Future<void> requestEmailOtp({required String email}) async {
    state = state.copyWith(
      status: AuthSessionStatus.requestingOtp,
      clearError: true,
      pendingEmail: email,
    );

    final result = await ref.read(requestEmailOtpProvider).call(
          email: email,
        );

    state = result.when(
      success: (challenge) => AuthSessionState(
        status: AuthSessionStatus.otpCodeSent,
        pendingEmail: email,
        otpChallengeId: challenge.challengeId,
        resendAfterSeconds: challenge.resendAfterSeconds,
      ),
      failure: (failure) => state.copyWith(
        status: AuthSessionStatus.error,
        errorMessage: failure.userMessage,
      ),
    );
  }

  Future<void> verifyEmailOtp(String otpCode) async {
    final email = state.pendingEmail;
    final challengeId = state.otpChallengeId;
    if (email == null || challengeId == null) {
      state = state.copyWith(
        status: AuthSessionStatus.error,
        errorMessage: 'Verification session expired. Request a new code.',
      );
      return;
    }

    state = state.copyWith(
      status: AuthSessionStatus.verifyingOtp,
      clearError: true,
    );

    final result = await ref.read(verifyEmailOtpProvider).call(
          email: email,
          challengeId: challengeId,
          otpCode: otpCode,
        );

    state = result.when(
      success: (user) => AuthSessionState(
        status: AuthSessionStatus.authenticated,
        user: user,
      ),
      failure: (failure) => state.copyWith(
        status: AuthSessionStatus.otpCodeSent,
        errorMessage: failure.userMessage,
      ),
    );
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(
      status: AuthSessionStatus.authenticatingWithGoogle,
      clearError: true,
    );

    final result = await ref.read(signInWithGoogleProvider).call();
    state = result.when(
      success: (user) => AuthSessionState(
        status: AuthSessionStatus.authenticated,
        user: user,
      ),
      failure: (failure) {
        if (failure is CancelledFailure) {
          return const AuthSessionState(
            status: AuthSessionStatus.unauthenticated,
          );
        }

        return AuthSessionState(
          status: AuthSessionStatus.error,
          errorMessage: failure.userMessage,
        );
      },
    );
  }

  void resetToEmailStep() {
    state = state.copyWith(
      status: AuthSessionStatus.unauthenticated,
      clearError: true,
      clearPending: true,
    );
  }

  Future<void> logout() async {
    await ref.read(logoutUserProvider).call();
    state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
  }
}
