import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';

class AuditLocalDataSource {
  static const List<Map<String, String>> _rawLogs = [
    {
      'id': 'AUD-2891',
      'timestamp': '2026-04-06 10:41:33',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'execute_screenshot',
      'target': 'EDGE-NODE-021',
      'status': 'Success',
      'detail': 'Screenshot captured (1920x1080, 2.4 MB)',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2890',
      'timestamp': '2026-04-06 10:38:17',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Policy',
      'event': 'update_policy',
      'target': 'Fleet-Group-A',
      'status': 'Success',
      'detail': 'Compliance policy v2.4 applied to 14 devices',
      'ip': '10.0.1.12'
    },
    {
      'id': 'AUD-2889',
      'timestamp': '2026-04-06 10:35:02',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'collect_filesystem',
      'target': 'PROD-SRV-014',
      'status': 'Failed',
      'detail': 'Connection timeout after 30s - device unreachable',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2888',
      'timestamp': '2026-04-06 10:29:44',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'device_offline',
      'target': 'PROD-SRV-014',
      'status': 'Failed',
      'detail': 'Heartbeat missed - device marked offline',
      'ip': '-'
    },
    {
      'id': 'AUD-2887',
      'timestamp': '2026-04-06 10:22:11',
      'actor': 'viewer@quoodle.io',
      'role': 'Viewer',
      'action': 'Auth',
      'event': 'login_attempt',
      'target': 'Auth Service',
      'status': 'Denied',
      'detail': 'Insufficient permissions - admin resource access blocked',
      'ip': '192.168.2.88'
    },
    {
      'id': 'AUD-2886',
      'timestamp': '2026-04-06 10:18:55',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'get_process_list',
      'target': 'WKS-FINANCE-07',
      'status': 'Success',
      'detail': '247 processes returned, 3 flagged as suspicious',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2885',
      'timestamp': '2026-04-06 10:14:30',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Config',
      'event': 'update_agent_config',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Agent config updated: telemetry_interval=30s, log_level=INFO',
      'ip': '10.0.1.12'
    },
    {
      'id': 'AUD-2884',
      'timestamp': '2026-04-06 10:09:18',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'upload_file',
      'target': 'EDGE-NODE-021',
      'status': 'Success',
      'detail': 'patch_v2.1.bin (4.2 MB) uploaded to /tmp/patches/',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2883',
      'timestamp': '2026-04-06 09:58:44',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'attestation_failure',
      'target': 'EDGE-NODE-021',
      'status': 'Failed',
      'detail': 'TPM attestation hash mismatch - quarantine enforced',
      'ip': '-'
    },
    {
      'id': 'AUD-2882',
      'timestamp': '2026-04-06 09:45:22',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Auth',
      'event': 'user_login',
      'target': 'Auth Service',
      'status': 'Success',
      'detail': 'MFA verified - session established (TTL: 8h)',
      'ip': '10.0.1.12'
    },
    {
      'id': 'AUD-2881',
      'timestamp': '2026-04-06 09:33:07',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'get_network_info',
      'target': 'PROD-SRV-014',
      'status': 'Success',
      'detail': '6 interfaces, 142 active connections returned',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2880',
      'timestamp': '2026-04-06 09:21:55',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'reboot_device',
      'target': 'WKS-FINANCE-07',
      'status': 'Pending',
      'detail': 'Reboot scheduled - awaiting device acknowledgment',
      'ip': '10.0.1.45'
    },
    {
      'id': 'AUD-2879',
      'timestamp': '2026-04-06 09:10:33',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Policy',
      'event': 'create_policy',
      'target': 'Finance-Group',
      'status': 'Success',
      'detail': 'New isolation policy created for Finance device group',
      'ip': '10.0.1.12'
    },
    {
      'id': 'AUD-2878',
      'timestamp': '2026-04-06 08:55:19',
      'actor': 'viewer@quoodle.io',
      'role': 'Viewer',
      'action': 'Device',
      'event': 'view_device_detail',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Device detail page accessed - read-only',
      'ip': '192.168.2.88'
    },
    {
      'id': 'AUD-2877',
      'timestamp': '2026-04-06 08:42:08',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'device_online',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Device reconnected after 4m 22s offline',
      'ip': '-'
    },
  ];

  List<AuditLogItem> getAuditLogs() {
    return _rawLogs
        .map(
          (log) => AuditLogItem(
            id: log['id'] ?? '',
            timestamp: log['timestamp'] ?? '',
            actor: log['actor'] ?? '',
            role: log['role'] ?? '',
            action: log['action'] ?? '',
            event: log['event'] ?? '',
            target: log['target'] ?? '',
            status: log['status'] ?? '',
            detail: log['detail'] ?? '',
            ip: log['ip'] ?? '',
          ),
        )
        .toList();
  }
}
