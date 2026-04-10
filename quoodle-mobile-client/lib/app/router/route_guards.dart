import 'package:secure_device_control/app/router/route_paths.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

class RouteGuards {
  const RouteGuards._();

  static String? authRedirect({
    required AuthSessionStatus authStatus,
    required String location,
  }) {
    final inAuthArea =
        location == RoutePaths.initial || location == RoutePaths.authentication;

    if (authStatus == AuthSessionStatus.authenticated && inAuthArea) {
      return RoutePaths.dashboard;
    }

    if (authStatus == AuthSessionStatus.unauthenticated && !inAuthArea) {
      return RoutePaths.authentication;
    }

    return null;
  }
}
