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
  static const String _controlPlaneBaseUrlRaw = String.fromEnvironment(
    'QDO_CONTROL_PLANE_BASE_URL',
    defaultValue: 'http://161.35.62.116:8088/api',
  );

  static String get controlPlaneBaseUrl =>
      _normalizeBaseUrl(_controlPlaneBaseUrlRaw);

  // Google OAuth server client used to request a one-time auth code.
  static const String googleServerClientId = String.fromEnvironment(
    'QDO_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '1036953333509-cfau5rlt0ntkqu0kmk2q3up4bukfn5so.apps.googleusercontent.com',
  );

  // Must match the redirect URI configured on Google OAuth and backend.
  static const String _googleRedirectUriRaw = String.fromEnvironment(
    'QDO_GOOGLE_REDIRECT_URI',
    defaultValue: '',
  );

  static String get googleRedirectUri {
    final fromDefine = _googleRedirectUriRaw.trim();
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    final base = Uri.tryParse(controlPlaneBaseUrl);
    if (base == null || base.host.isEmpty) {
      return 'http://161.35.62.116:3000/api/auth/google/callback';
    }

    return Uri(
      scheme: base.scheme.isEmpty ? 'http' : base.scheme,
      host: base.host,
      port: 3000,
      path: '/api/auth/google/callback',
    ).toString();
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
