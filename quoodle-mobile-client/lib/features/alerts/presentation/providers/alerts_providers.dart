import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/alerts/data/datasources/alerts_local_data_source.dart';
import 'package:secure_device_control/features/alerts/data/repositories/alerts_repository_impl.dart';
import 'package:secure_device_control/features/alerts/domain/repositories/alerts_repository.dart';
import 'package:secure_device_control/features/alerts/domain/usecases/acknowledge_alert.dart';
import 'package:secure_device_control/features/alerts/domain/usecases/acknowledge_all_alerts.dart';
import 'package:secure_device_control/features/alerts/domain/usecases/get_alerts.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_controller.dart';
import 'package:secure_device_control/features/alerts/presentation/providers/alerts_state.dart';

final alertsLocalDataSourceProvider = Provider<AlertsLocalDataSource>((ref) {
  return AlertsLocalDataSource();
});

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return AlertsRepositoryImpl(ref.read(alertsLocalDataSourceProvider));
});

final getAlertsProvider = Provider<GetAlerts>((ref) {
  return GetAlerts(ref.read(alertsRepositoryProvider));
});

final acknowledgeAlertProvider = Provider<AcknowledgeAlert>((ref) {
  return AcknowledgeAlert(ref.read(alertsRepositoryProvider));
});

final acknowledgeAllAlertsProvider = Provider<AcknowledgeAllAlerts>((ref) {
  return AcknowledgeAllAlerts(ref.read(alertsRepositoryProvider));
});

final alertsControllerProvider =
    AutoDisposeNotifierProvider<AlertsController, AlertsState>(
  AlertsController.new,
);
