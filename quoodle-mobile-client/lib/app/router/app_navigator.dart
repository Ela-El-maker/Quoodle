import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:secure_device_control/app/router/app_router.dart';
import 'package:secure_device_control/app/router/route_paths.dart';

enum AppRoute {
  initial,
  authentication,
  dashboard,
  devices,
  deviceDetail,
  commandTimeline,
  alerts,
  qrScanner,
  sendCommand,
  settings,
  scheduler,
  notificationCenter,
  auditLog,
  analytics,
}

enum ProfileTabTarget {
  authentication,
  settings,
}

class AppNavigator {
  const AppNavigator._();

  static String pathFor(AppRoute route) {
    switch (route) {
      case AppRoute.initial:
        return RoutePaths.initial;
      case AppRoute.authentication:
        return RoutePaths.authentication;
      case AppRoute.dashboard:
        return RoutePaths.dashboard;
      case AppRoute.devices:
        return RoutePaths.devices;
      case AppRoute.deviceDetail:
        return RoutePaths.deviceDetail;
      case AppRoute.commandTimeline:
        return RoutePaths.commandTimeline;
      case AppRoute.alerts:
        return RoutePaths.alerts;
      case AppRoute.qrScanner:
        return RoutePaths.qrScanner;
      case AppRoute.sendCommand:
        return RoutePaths.sendCommand;
      case AppRoute.settings:
        return RoutePaths.settings;
      case AppRoute.scheduler:
        return RoutePaths.scheduler;
      case AppRoute.notificationCenter:
        return RoutePaths.notificationCenter;
      case AppRoute.auditLog:
        return RoutePaths.auditLog;
      case AppRoute.analytics:
        return RoutePaths.analytics;
    }
  }

  static String tabRouteForIndex(
    int index, {
    ProfileTabTarget profileTabTarget = ProfileTabTarget.authentication,
  }) {
    final tabRoutes = <String>[
      RoutePaths.dashboard,
      RoutePaths.devices,
      RoutePaths.commandTimeline,
      RoutePaths.alerts,
      profileTabTarget == ProfileTabTarget.authentication
          ? RoutePaths.authentication
          : RoutePaths.settings,
    ];

    if (index < 0 || index >= tabRoutes.length) {
      return tabRoutes.first;
    }

    return tabRoutes[index];
  }

  static void navigateToTab(
    BuildContext context,
    int index, {
    ProfileTabTarget profileTabTarget = ProfileTabTarget.authentication,
  }) {
    _router(context).go(
      tabRouteForIndex(index, profileTabTarget: profileTabTarget),
    );
  }

  static Future<T?> push<T>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
  }) {
    return _router(context).push<T>(
      pathFor(route),
      extra: arguments,
    );
  }

  static Future<T?> replaceStackWith<T>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
  }) {
    _router(context).go(
      pathFor(route),
      extra: arguments,
    );
    return Future<T?>.value(null);
  }

  static Future<T?> pushAndPruneUntil<T>(
    BuildContext context,
    AppRoute route, {
    required RoutePredicate predicate,
    Object? arguments,
  }) {
    // Kept for compatibility with legacy callers. In declarative routing mode
    // we normalize this to a stack-replacing go() transition.
    _router(context).go(
      pathFor(route),
      extra: arguments,
    );
    return Future<T?>.value(null);
  }

  static bool popOrGo(
    BuildContext context,
    AppRoute fallback, {
    Object? arguments,
  }) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return true;
    }
    _router(context).go(pathFor(fallback), extra: arguments);
    return false;
  }

  static GoRouter _router(BuildContext context) {
    return GoRouter.maybeOf(context) ?? AppRouter.goRouter;
  }
}
