import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';

class AlertsLocalDataSource {
  List<AlertItem> _alerts = [
    const AlertItem(
      id: 'alert-041',
      severity: AlertSeverityType.critical,
      deviceId: 'dev-021',
      deviceName: 'EDGE-NODE-021',
      message:
          'Attestation failure - device identity could not be verified. Quarantine enforced.',
      timestamp: '10:58 AM',
      acknowledged: false,
      category: 'security',
    ),
    const AlertItem(
      id: 'alert-039',
      severity: AlertSeverityType.high,
      deviceId: 'dev-014',
      deviceName: 'PROD-SRV-014',
      message:
          'Device offline - no heartbeat received for 18 minutes. Last command: collect_telemetry (failed).',
      timestamp: '10:44 AM',
      acknowledged: false,
      category: 'availability',
    ),
    const AlertItem(
      id: 'alert-037',
      severity: AlertSeverityType.high,
      deviceId: 'dev-007',
      deviceName: 'WKS-FINANCE-07',
      message:
          'Policy drift detected - reported hash abc3f9 does not match expected 7f3a9e.',
      timestamp: '10:38 AM',
      acknowledged: false,
      category: 'compliance',
    ),
    const AlertItem(
      id: 'alert-035',
      severity: AlertSeverityType.warning,
      deviceId: 'dev-007',
      deviceName: 'WKS-FINANCE-07',
      message:
          'Agent version 2.0.9 is below minimum recommended version (2.1.x). Upgrade required.',
      timestamp: '09:12 AM',
      acknowledged: false,
      category: 'maintenance',
    ),
    const AlertItem(
      id: 'alert-033',
      severity: AlertSeverityType.warning,
      deviceId: 'dev-019',
      deviceName: 'EDGE-NODE-019',
      message:
          'Disk usage at 84% - approaching threshold. Review and clean up if needed.',
      timestamp: '08:45 AM',
      acknowledged: true,
      category: 'performance',
    ),
    const AlertItem(
      id: 'alert-031',
      severity: AlertSeverityType.info,
      deviceId: 'dev-001',
      deviceName: 'PROD-SRV-001',
      message:
          'Scheduled compliance scan completed - all 14 rules passed. No action required.',
      timestamp: '08:00 AM',
      acknowledged: true,
      category: 'compliance',
    ),
    const AlertItem(
      id: 'alert-028',
      severity: AlertSeverityType.info,
      deviceId: 'dev-015',
      deviceName: 'PROD-SRV-015',
      message:
          'Agent updated to version 2.1.4 successfully. Policy re-applied.',
      timestamp: '07:30 AM',
      acknowledged: true,
      category: 'maintenance',
    ),
  ];

  List<AlertItem> getAlerts() {
    return List<AlertItem>.unmodifiable(_alerts);
  }

  void acknowledgeAlert(String alertId) {
    _alerts = _alerts
        .map(
          (alert) =>
              alert.id == alertId ? alert.copyWith(acknowledged: true) : alert,
        )
        .toList();
  }

  void acknowledgeAll() {
    _alerts =
        _alerts.map((alert) => alert.copyWith(acknowledged: true)).toList();
  }
}
