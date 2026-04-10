import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';

abstract class AlertsRepository {
  List<AlertItem> getAlerts();

  void acknowledgeAlert(String alertId);

  void acknowledgeAll();
}
