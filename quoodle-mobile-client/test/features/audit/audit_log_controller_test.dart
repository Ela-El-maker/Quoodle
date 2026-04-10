import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';
import 'package:secure_device_control/features/audit/domain/repositories/audit_repository.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_providers.dart';

class _FakeAuditRepository implements AuditRepository {
  _FakeAuditRepository(this._logs);
  final List<AuditLogItem> _logs;

  @override
  List<AuditLogItem> getAuditLogs() => List<AuditLogItem>.unmodifiable(_logs);
}

void main() {
  test('AuditLogController filters by query/action/status', () {
    final container = ProviderContainer(
      overrides: [
        auditRepositoryProvider.overrideWithValue(
          _FakeAuditRepository([
            const AuditLogItem(
              id: '1',
              timestamp: '2026-04-01',
              actor: 'operator@x',
              role: 'Operator',
              action: 'Command',
              event: 'collect_filesystem',
              target: 'DEV-1',
              status: 'Failed',
              detail: 'timeout',
              ip: '10.0.0.1',
            ),
            const AuditLogItem(
              id: '2',
              timestamp: '2026-04-01',
              actor: 'admin@x',
              role: 'Admin',
              action: 'Policy',
              event: 'update_policy',
              target: 'Fleet',
              status: 'Success',
              detail: 'ok',
              ip: '10.0.0.2',
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(auditLogControllerProvider.notifier);
    expect(container.read(auditLogControllerProvider).filteredLogs.length, 2);

    controller.setSearchQuery('filesystem');
    expect(container.read(auditLogControllerProvider).filteredLogs.length, 1);

    controller.setSearchQuery('');
    controller.setActionFilter('Policy');
    controller.setStatusFilter('Success');
    expect(
      container.read(auditLogControllerProvider).filteredLogs.single.id,
      '2',
    );
  });
}
