import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';
import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';

class GetAlerts {
  const GetAlerts(this._repository);

  final AlertsRepository _repository;

  List<AlertItem> call() {
    return _repository.getAlerts();
  }
}
