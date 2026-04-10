import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/audit/data/datasources/audit_local_data_source.dart';
import 'package:secure_device_control/features/audit/data/repositories/audit_repository_impl.dart';
import 'package:secure_device_control/features/audit/domain/repositories/audit_repository.dart';
import 'package:secure_device_control/features/audit/domain/usecases/get_audit_logs.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_controller.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_state.dart';

final auditLocalDataSourceProvider = Provider<AuditLocalDataSource>((ref) {
  return AuditLocalDataSource();
});

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepositoryImpl(ref.read(auditLocalDataSourceProvider));
});

final getAuditLogsProvider = Provider<GetAuditLogs>((ref) {
  return GetAuditLogs(ref.read(auditRepositoryProvider));
});

final auditLogControllerProvider =
    NotifierProvider<AuditLogController, AuditLogState>(
  AuditLogController.new,
);
