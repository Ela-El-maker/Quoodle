import 'package:secure_device_control/features/audit/data/datasources/audit_local_data_source.dart';
import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';
import 'package:secure_device_control/features/audit/domain/repositories/audit_repository.dart';

class AuditRepositoryImpl implements AuditRepository {
  const AuditRepositoryImpl(this._localDataSource);

  final AuditLocalDataSource _localDataSource;

  @override
  List<AuditLogItem> getAuditLogs() {
    return _localDataSource.getAuditLogs();
  }
}
