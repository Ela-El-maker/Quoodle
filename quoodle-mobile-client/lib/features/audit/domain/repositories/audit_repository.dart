import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';

abstract class AuditRepository {
  List<AuditLogItem> getAuditLogs();
}
