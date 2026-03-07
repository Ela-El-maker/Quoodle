import '../services/session_store.dart';

enum UserRole {
  viewer,
  operator,
  admin,
}

class Rbac {
  static UserRole parseRole(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'operator':
        return UserRole.operator;
      default:
        return UserRole.viewer;
    }
  }

  static UserRole currentRole() => parseRole(SessionStore.userRole);

  static bool hasAtLeast(UserRole required, {UserRole? role}) {
    final current = role ?? currentRole();
    return _weight(current) >= _weight(required);
  }

  static int _weight(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 3;
      case UserRole.operator:
        return 2;
      case UserRole.viewer:
        return 1;
    }
  }

  static String label(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.operator:
        return 'Operator';
      case UserRole.viewer:
        return 'Viewer';
    }
  }
}
