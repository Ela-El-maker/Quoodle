import 'package:secure_device_control/features/alerts/data/datasources/alerts_local_data_source.dart';
import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';
import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';

class AlertsRepositoryImpl implements AlertsRepository {
  AlertsRepositoryImpl(this._localDataSource);

  final AlertsLocalDataSource _localDataSource;

  @override
  List<AlertItem> getAlerts() {
    return _localDataSource.getAlerts();
  }

  @override
  void acknowledgeAlert(String alertId) {
    _localDataSource.acknowledgeAlert(alertId);
  }

  @override
  void acknowledgeAll() {
    _localDataSource.acknowledgeAll();
  }
}
