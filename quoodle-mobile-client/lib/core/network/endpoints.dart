class Endpoints {
  const Endpoints._();

  static const requestOtp = '/auth/request-otp';
  static const verifyOtp = '/auth/verify-otp';
  static const exchangeGoogleCode = '/auth/google/exchange';
  static const refreshSession = '/token/refresh';
  static const profile = '/me';
  static const logout = '/logout';
  static const dashboardSummary = '/dashboard/summary';
  static const devices = '/devices';
  static const alerts = '/alerts';
  static const telemetryFleetSummary = '/telemetry/fleet/summary';
  static const telemetryFleetTimeseries = '/telemetry/fleet/timeseries';
  static const telemetryActivity = '/telemetry/activity';
  static const commands = '/commands';
  static const pairConfirm = '/pair/confirm';
  static String pairSession(String pairSessionId) =>
      '/pair/session/$pairSessionId';

  static String commandById(String commandId) => '/commands/$commandId';
  static String deviceCommands(String deviceId) =>
      '/devices/$deviceId/commands';
  static String telemetryDeviceLatest(String deviceId) =>
      '/telemetry/devices/$deviceId/latest';
  static String telemetryDeviceHistory(String deviceId) =>
      '/telemetry/devices/$deviceId/history';
}
