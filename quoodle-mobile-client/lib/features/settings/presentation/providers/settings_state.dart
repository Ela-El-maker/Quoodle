import 'package:secure_device_control/features/settings/domain/entities/session_entry.dart';

class SettingsState {
  const SettingsState({
    required this.isLoading,
    this.errorMessage,
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
    return const SettingsState(
      isLoading: true,
      notifCriticalAlerts: true,
      notifDeviceOffline: true,
      notifCommandFailed: true,
      notifPolicyViolation: true,
      notifNewDevice: false,
      notifTelemetryAnomaly: false,
      notifAuditEvents: false,
      notifWeeklyReport: true,
      sessions: <SessionEntry>[],
    );
  }

  final bool isLoading;
  final String? errorMessage;
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
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
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
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
