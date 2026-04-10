import 'package:secure_device_control/features/alerts/domain/entities/alert_item.dart';

enum AlertsFilter { all, critical, high, warning, info }

extension AlertsFilterLabel on AlertsFilter {
  String get label {
    switch (this) {
      case AlertsFilter.all:
        return 'All';
      case AlertsFilter.critical:
        return 'Critical';
      case AlertsFilter.high:
        return 'High';
      case AlertsFilter.warning:
        return 'Warning';
      case AlertsFilter.info:
        return 'Info';
    }
  }

  AlertSeverityType? get severity {
    switch (this) {
      case AlertsFilter.all:
        return null;
      case AlertsFilter.critical:
        return AlertSeverityType.critical;
      case AlertsFilter.high:
        return AlertSeverityType.high;
      case AlertsFilter.warning:
        return AlertSeverityType.warning;
      case AlertsFilter.info:
        return AlertSeverityType.info;
    }
  }
}

class AlertsState {
  const AlertsState({
    required this.isLoading,
    required this.selectedFilter,
    required this.alerts,
  });

  factory AlertsState.initial() {
    return const AlertsState(
      isLoading: true,
      selectedFilter: AlertsFilter.all,
      alerts: <AlertItem>[],
    );
  }

  final bool isLoading;
  final AlertsFilter selectedFilter;
  final List<AlertItem> alerts;

  List<AlertItem> get filteredAlerts {
    final severity = selectedFilter.severity;
    if (severity == null) {
      return alerts;
    }

    return alerts.where((alert) => alert.severity == severity).toList();
  }

  int get unackedCount => alerts.where((a) => !a.acknowledged).length;

  AlertsState copyWith({
    bool? isLoading,
    AlertsFilter? selectedFilter,
    List<AlertItem>? alerts,
  }) {
    return AlertsState(
      isLoading: isLoading ?? this.isLoading,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      alerts: alerts ?? this.alerts,
    );
  }
}
