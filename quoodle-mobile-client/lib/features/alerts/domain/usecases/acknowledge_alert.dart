import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';

class AcknowledgeAlert {
  const AcknowledgeAlert(this._repository);

  final AlertsRepository _repository;

  void call(String alertId) {
    _repository.acknowledgeAlert(alertId);
  }
}
