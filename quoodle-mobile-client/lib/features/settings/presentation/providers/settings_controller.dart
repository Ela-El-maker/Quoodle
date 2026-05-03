import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';
import 'package:secure_device_control/features/settings/domain/entities/session_entry.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_state.dart';

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    Future<void>.microtask(_hydrate);
    return SettingsState.initial();
  }

  Future<void> _hydrate() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final kv = ref.read(keyValueStorageProvider);
      final secureStorage = ref.read(secureStorageServiceProvider);

      final notifCriticalAlerts =
          await kv.getBool(StorageKeys.notifCriticalAlerts);
      final notifDeviceOffline =
          await kv.getBool(StorageKeys.notifDeviceOffline);
      final notifCommandFailed =
          await kv.getBool(StorageKeys.notifCommandFailed);
      final notifPolicyViolation =
          await kv.getBool(StorageKeys.notifPolicyViolation);
      final notifNewDevice = await kv.getBool(StorageKeys.notifNewDevice);
      final notifTelemetryAnomaly =
          await kv.getBool(StorageKeys.notifTelemetryAnomaly);
      final notifAuditEvents = await kv.getBool(StorageKeys.notifAuditEvents);
      final notifWeeklyReport = await kv.getBool(StorageKeys.notifWeeklyReport);

      final sessionId = await secureStorage.read(StorageKeys.sessionId);
      final sessions = <SessionEntry>[
        if (sessionId != null && sessionId.isNotEmpty)
          SessionEntry(
            id: sessionId,
            device: 'Current Mobile Session',
            location: '-',
            ip: '-',
            lastActive: DateTime.now(),
            isCurrent: true,
          ),
      ];

      state = state.copyWith(
        isLoading: false,
        notifCriticalAlerts: notifCriticalAlerts ?? state.notifCriticalAlerts,
        notifDeviceOffline: notifDeviceOffline ?? state.notifDeviceOffline,
        notifCommandFailed: notifCommandFailed ?? state.notifCommandFailed,
        notifPolicyViolation:
            notifPolicyViolation ?? state.notifPolicyViolation,
        notifNewDevice: notifNewDevice ?? state.notifNewDevice,
        notifTelemetryAnomaly:
            notifTelemetryAnomaly ?? state.notifTelemetryAnomaly,
        notifAuditEvents: notifAuditEvents ?? state.notifAuditEvents,
        notifWeeklyReport: notifWeeklyReport ?? state.notifWeeklyReport,
        sessions: sessions,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to load settings data.',
      );
    }
  }

  Future<void> _setNotif(String key, bool value) async {
    final kv = ref.read(keyValueStorageProvider);
    await kv.setBool(key, value);
  }

  void setNotifCriticalAlerts(bool value) {
    state = state.copyWith(notifCriticalAlerts: value);
    _setNotif(StorageKeys.notifCriticalAlerts, value);
  }

  void setNotifDeviceOffline(bool value) {
    state = state.copyWith(notifDeviceOffline: value);
    _setNotif(StorageKeys.notifDeviceOffline, value);
  }

  void setNotifCommandFailed(bool value) {
    state = state.copyWith(notifCommandFailed: value);
    _setNotif(StorageKeys.notifCommandFailed, value);
  }

  void setNotifPolicyViolation(bool value) {
    state = state.copyWith(notifPolicyViolation: value);
    _setNotif(StorageKeys.notifPolicyViolation, value);
  }

  void setNotifNewDevice(bool value) {
    state = state.copyWith(notifNewDevice: value);
    _setNotif(StorageKeys.notifNewDevice, value);
  }

  void setNotifTelemetryAnomaly(bool value) {
    state = state.copyWith(notifTelemetryAnomaly: value);
    _setNotif(StorageKeys.notifTelemetryAnomaly, value);
  }

  void setNotifAuditEvents(bool value) {
    state = state.copyWith(notifAuditEvents: value);
    _setNotif(StorageKeys.notifAuditEvents, value);
  }

  void setNotifWeeklyReport(bool value) {
    state = state.copyWith(notifWeeklyReport: value);
    _setNotif(StorageKeys.notifWeeklyReport, value);
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
