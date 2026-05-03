class StorageKeys {
  const StorageKeys._();

  static const authToken = 'auth.token';
  static const refreshToken = 'auth.refresh_token';
  static const sessionId = 'auth.session_id';
  static const userId = 'auth.user_id';
  static const userRole = 'auth.user_role';
  static const userEmail = 'auth.user_email';
  static const userName = 'auth.user_name';
  static const isAuthenticated = 'auth.is_authenticated';
  static const deviceFingerprint = 'device.fingerprint';

  static const notifCriticalAlerts = 'settings.notif_critical_alerts';
  static const notifDeviceOffline = 'settings.notif_device_offline';
  static const notifCommandFailed = 'settings.notif_command_failed';
  static const notifPolicyViolation = 'settings.notif_policy_violation';
  static const notifNewDevice = 'settings.notif_new_device';
  static const notifTelemetryAnomaly = 'settings.notif_telemetry_anomaly';
  static const notifAuditEvents = 'settings.notif_audit_events';
  static const notifWeeklyReport = 'settings.notif_weekly_report';
}
