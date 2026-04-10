enum AppEnvironment { dev, staging, production }

class AppEnv {
  const AppEnv._();

  static const AppEnvironment environment = AppEnvironment.dev;

  static String get name {
    switch (environment) {
      case AppEnvironment.dev:
        return 'dev';
      case AppEnvironment.staging:
        return 'staging';
      case AppEnvironment.production:
        return 'production';
    }
  }
}
