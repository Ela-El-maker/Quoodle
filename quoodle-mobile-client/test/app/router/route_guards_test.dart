import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/app/router/route_guards.dart';
import 'package:secure_device_control/app/router/route_paths.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

void main() {
  group('RouteGuards.authRedirect', () {
    test('redirects authenticated users away from auth area', () {
      final redirect = RouteGuards.authRedirect(
        authStatus: AuthSessionStatus.authenticated,
        location: RoutePaths.authentication,
      );

      expect(redirect, RoutePaths.dashboard);
    });

    test('redirects unauthenticated users away from protected routes', () {
      final redirect = RouteGuards.authRedirect(
        authStatus: AuthSessionStatus.unauthenticated,
        location: RoutePaths.dashboard,
      );

      expect(redirect, RoutePaths.authentication);
    });

    test('allows unauthenticated users on auth area', () {
      final redirect = RouteGuards.authRedirect(
        authStatus: AuthSessionStatus.unauthenticated,
        location: RoutePaths.authentication,
      );

      expect(redirect, isNull);
    });

    test('does not force redirect for unknown session state', () {
      final redirect = RouteGuards.authRedirect(
        authStatus: AuthSessionStatus.unknown,
        location: RoutePaths.dashboard,
      );

      expect(redirect, isNull);
    });
  });
}
