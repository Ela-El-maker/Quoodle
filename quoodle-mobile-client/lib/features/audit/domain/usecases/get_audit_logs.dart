import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';
import 'package:secure_device_control/features/audit/domain/repositories/audit_repository.dart';

class GetAuditLogs {
  const GetAuditLogs(this._repository);

  final AuditRepository _repository;

  List<AuditLogItem> call() {
    return _repository.getAuditLogs();
  }
}
