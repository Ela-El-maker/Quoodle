import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_state.dart';

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    return SettingsState.initial();
  }

  void setNotifCriticalAlerts(bool value) {
    state = state.copyWith(notifCriticalAlerts: value);
  }

  void setNotifDeviceOffline(bool value) {
    state = state.copyWith(notifDeviceOffline: value);
  }

  void setNotifCommandFailed(bool value) {
    state = state.copyWith(notifCommandFailed: value);
  }

  void setNotifPolicyViolation(bool value) {
    state = state.copyWith(notifPolicyViolation: value);
  }

  void setNotifNewDevice(bool value) {
    state = state.copyWith(notifNewDevice: value);
  }

  void setNotifTelemetryAnomaly(bool value) {
    state = state.copyWith(notifTelemetryAnomaly: value);
  }

  void setNotifAuditEvents(bool value) {
    state = state.copyWith(notifAuditEvents: value);
  }

  void setNotifWeeklyReport(bool value) {
    state = state.copyWith(notifWeeklyReport: value);
  }

  void revokeSession(String sessionId) {
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
    );
  }

  void revokeAllOtherSessions() {
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.isCurrent).toList(),
    );
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
