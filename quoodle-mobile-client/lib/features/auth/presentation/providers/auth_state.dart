import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';

enum AuthSessionStatus {
  unknown,
  unauthenticated,
  requestingOtp,
  otpCodeSent,
  verifyingOtp,
  authenticatingWithGoogle,
  authenticated,
  refreshing,
  error,
}

class AuthSessionState {
  const AuthSessionState({
    required this.status,
    this.user,
    this.errorMessage,
    this.pendingEmail,
    this.otpChallengeId,
    this.resendAfterSeconds,
  });

  factory AuthSessionState.initial() =>
      const AuthSessionState(status: AuthSessionStatus.unknown);

  final AuthSessionStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final String? pendingEmail;
  final String? otpChallengeId;
  final int? resendAfterSeconds;

  bool get isLoading =>
      status == AuthSessionStatus.requestingOtp ||
      status == AuthSessionStatus.verifyingOtp ||
      status == AuthSessionStatus.authenticatingWithGoogle ||
      status == AuthSessionStatus.refreshing;

  bool get requiresOtpCode => status == AuthSessionStatus.otpCodeSent;

  AuthSessionState copyWith({
    AuthSessionStatus? status,
    AuthUser? user,
    String? errorMessage,
    String? pendingEmail,
    String? otpChallengeId,
    int? resendAfterSeconds,
    bool clearError = false,
    bool clearPending = false,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingEmail: clearPending ? null : (pendingEmail ?? this.pendingEmail),
      otpChallengeId:
          clearPending ? null : (otpChallengeId ?? this.otpChallengeId),
      resendAfterSeconds:
          clearPending ? null : (resendAfterSeconds ?? this.resendAfterSeconds),
    );
  }
}
