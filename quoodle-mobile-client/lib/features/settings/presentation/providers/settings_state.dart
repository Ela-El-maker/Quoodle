import 'package:secure_device_control/features/settings/domain/entities/session_entry.dart';

class SettingsState {
  const SettingsState({
    required this.notifCriticalAlerts,
    required this.notifDeviceOffline,
    required this.notifCommandFailed,
    required this.notifPolicyViolation,
    required this.notifNewDevice,
    required this.notifTelemetryAnomaly,
    required this.notifAuditEvents,
    required this.notifWeeklyReport,
    required this.sessions,
  });

  factory SettingsState.initial() {
    return SettingsState(
      notifCriticalAlerts: true,
      notifDeviceOffline: true,
      notifCommandFailed: true,
      notifPolicyViolation: true,
      notifNewDevice: false,
      notifTelemetryAnomaly: false,
      notifAuditEvents: false,
      notifWeeklyReport: true,
      sessions: [
        SessionEntry(
          id: 'sess_001',
          device: 'Chrome - macOS',
          location: 'San Francisco, US',
          ip: '192.168.1.42',
          lastActive: DateTime.now().subtract(const Duration(minutes: 2)),
          isCurrent: true,
        ),
        SessionEntry(
          id: 'sess_002',
          device: 'Firefox - Windows 11',
          location: 'New York, US',
          ip: '10.0.0.15',
          lastActive: DateTime.now().subtract(const Duration(hours: 3)),
          isCurrent: false,
        ),
        SessionEntry(
          id: 'sess_003',
          device: 'Safari - iPhone 15',
          location: 'San Francisco, US',
          ip: '172.16.0.8',
          lastActive: DateTime.now().subtract(const Duration(days: 1)),
          isCurrent: false,
        ),
      ],
    );
  }

  final bool notifCriticalAlerts;
  final bool notifDeviceOffline;
  final bool notifCommandFailed;
  final bool notifPolicyViolation;
  final bool notifNewDevice;
  final bool notifTelemetryAnomaly;
  final bool notifAuditEvents;
  final bool notifWeeklyReport;
  final List<SessionEntry> sessions;

  SettingsState copyWith({
    bool? notifCriticalAlerts,
    bool? notifDeviceOffline,
    bool? notifCommandFailed,
    bool? notifPolicyViolation,
    bool? notifNewDevice,
    bool? notifTelemetryAnomaly,
    bool? notifAuditEvents,
    bool? notifWeeklyReport,
    List<SessionEntry>? sessions,
  }) {
    return SettingsState(
      notifCriticalAlerts: notifCriticalAlerts ?? this.notifCriticalAlerts,
      notifDeviceOffline: notifDeviceOffline ?? this.notifDeviceOffline,
      notifCommandFailed: notifCommandFailed ?? this.notifCommandFailed,
      notifPolicyViolation: notifPolicyViolation ?? this.notifPolicyViolation,
      notifNewDevice: notifNewDevice ?? this.notifNewDevice,
      notifTelemetryAnomaly:
          notifTelemetryAnomaly ?? this.notifTelemetryAnomaly,
      notifAuditEvents: notifAuditEvents ?? this.notifAuditEvents,
      notifWeeklyReport: notifWeeklyReport ?? this.notifWeeklyReport,
      sessions: sessions ?? this.sessions,
    );
  }
}
