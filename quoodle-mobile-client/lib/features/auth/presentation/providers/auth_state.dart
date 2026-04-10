import 'package:secure_device_control/features/auth/domain/entities/auth_user.dart';

enum AuthSessionStatus {
  unknown,
  unauthenticated,
  authenticating,
  twoFactorRequired,
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
    this.pendingPassword,
  });

  factory AuthSessionState.initial() =>
      const AuthSessionState(status: AuthSessionStatus.unknown);

  final AuthSessionStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final String? pendingEmail;
  final String? pendingPassword;

  bool get isLoading =>
      status == AuthSessionStatus.authenticating ||
      status == AuthSessionStatus.refreshing;

  bool get requiresTwoFactor => status == AuthSessionStatus.twoFactorRequired;

  AuthSessionState copyWith({
    AuthSessionStatus? status,
    AuthUser? user,
    String? errorMessage,
    String? pendingEmail,
    String? pendingPassword,
    bool clearError = false,
    bool clearPending = false,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingEmail: clearPending ? null : (pendingEmail ?? this.pendingEmail),
      pendingPassword:
          clearPending ? null : (pendingPassword ?? this.pendingPassword),
    );
  }
}
