import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_providers.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_state.dart';

class AuditLogController extends Notifier<AuditLogState> {
  @override
  AuditLogState build() {
    return AuditLogState.initial().copyWith(
      logs: ref.read(getAuditLogsProvider).call(),
    );
  }

  void toggleFilters() {
    state = state.copyWith(showFilters: !state.showFilters);
  }

  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value);
  }

  void setActionFilter(String value) {
    state = state.copyWith(selectedAction: value);
  }

  void setRoleFilter(String value) {
    state = state.copyWith(selectedRole: value);
  }

  void setStatusFilter(String value) {
    state = state.copyWith(selectedStatus: value);
  }
}
