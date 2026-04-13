class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.twoFactorEnabled,
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final bool twoFactorEnabled;
}
