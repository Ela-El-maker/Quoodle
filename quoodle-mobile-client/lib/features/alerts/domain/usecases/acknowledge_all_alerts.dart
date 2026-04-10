import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';

class AcknowledgeAllAlerts {
  const AcknowledgeAllAlerts(this._repository);

  final AlertsRepository _repository;

  void call() {
    _repository.acknowledgeAll();
  }
}
