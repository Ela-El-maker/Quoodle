class AuditLogItem {
  const AuditLogItem({
    required this.id,
    required this.timestamp,
    required this.actor,
    required this.role,
    required this.action,
    required this.event,
    required this.target,
    required this.status,
    required this.detail,
    required this.ip,
  });

  final String id;
  final String timestamp;
  final String actor;
  final String role;
  final String action;
  final String event;
  final String target;
  final String status;
  final String detail;
  final String ip;
}
