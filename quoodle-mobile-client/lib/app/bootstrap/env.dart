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

  // Set with:
  // flutter run --dart-define=QDO_CONTROL_PLANE_BASE_URL=https://api.example.com/api
  static const String controlPlaneBaseUrl = String.fromEnvironment(
    'QDO_CONTROL_PLANE_BASE_URL',
    defaultValue: 'http://192.168.0.102:8088/api',
  );

  // Google OAuth server client used to request a one-time auth code.
  static const String googleServerClientId = String.fromEnvironment(
    'QDO_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '1036953333509-cfau5rlt0ntkqu0kmk2q3up4bukfn5so.apps.googleusercontent.com',
  );

  // Must match the redirect URI configured on Google OAuth and backend.
  static const String googleRedirectUri = String.fromEnvironment(
    'QDO_GOOGLE_REDIRECT_URI',
    defaultValue: 'http://192.168.0.102:3000/api/auth/google/callback',
  );
}
