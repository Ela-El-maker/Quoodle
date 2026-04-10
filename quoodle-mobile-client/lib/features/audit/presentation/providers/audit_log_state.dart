import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';

class AuditLogState {
  const AuditLogState({
    required this.searchQuery,
    required this.selectedAction,
    required this.selectedRole,
    required this.selectedStatus,
    required this.showFilters,
    required this.logs,
  });

  factory AuditLogState.initial() {
    return const AuditLogState(
      searchQuery: '',
      selectedAction: 'All',
      selectedRole: 'All',
      selectedStatus: 'All',
      showFilters: false,
      logs: <AuditLogItem>[],
    );
  }

  static const List<String> actionFilters = [
    'All',
    'Command',
    'Device',
    'Auth',
    'Policy',
    'Config',
  ];
  static const List<String> roleFilters = [
    'All',
    'Operator',
    'Admin',
    'Viewer',
    'System',
  ];
  static const List<String> statusFilters = [
    'All',
    'Success',
    'Failed',
    'Pending',
    'Denied',
  ];

  final String searchQuery;
  final String selectedAction;
  final String selectedRole;
  final String selectedStatus;
  final bool showFilters;
  final List<AuditLogItem> logs;

  List<AuditLogItem> get filteredLogs {
    final query = searchQuery.toLowerCase();

    return logs.where((log) {
      final matchSearch = searchQuery.isEmpty ||
          log.event.toLowerCase().contains(query) ||
          log.actor.toLowerCase().contains(query) ||
          log.target.toLowerCase().contains(query) ||
          log.id.toLowerCase().contains(query);
      final matchAction =
          selectedAction == 'All' || log.action == selectedAction;
      final matchRole = selectedRole == 'All' || log.role == selectedRole;
      final matchStatus =
          selectedStatus == 'All' || log.status == selectedStatus;
      return matchSearch && matchAction && matchRole && matchStatus;
    }).toList();
  }

  AuditLogState copyWith({
    String? searchQuery,
    String? selectedAction,
    String? selectedRole,
    String? selectedStatus,
    bool? showFilters,
    List<AuditLogItem>? logs,
  }) {
    return AuditLogState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedAction: selectedAction ?? this.selectedAction,
      selectedRole: selectedRole ?? this.selectedRole,
      selectedStatus: selectedStatus ?? this.selectedStatus,
      showFilters: showFilters ?? this.showFilters,
      logs: logs ?? this.logs,
    );
  }
}
