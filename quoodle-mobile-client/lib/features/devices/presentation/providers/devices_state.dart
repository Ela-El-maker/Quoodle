import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';

enum DevicesFilter { all, online, offline, degraded }

extension DevicesFilterLabel on DevicesFilter {
  String get label {
    switch (this) {
      case DevicesFilter.all:
        return 'All';
      case DevicesFilter.online:
        return 'Online';
      case DevicesFilter.offline:
        return 'Offline';
      case DevicesFilter.degraded:
        return 'Degraded';
    }
  }
}

class DevicesState {
  const DevicesState({
    required this.isLoading,
    required this.errorMessage,
    required this.searchQuery,
    required this.selectedFilter,
    required this.allDevices,
    required this.filteredDevices,
  });

  factory DevicesState.initial() {
    return const DevicesState(
      isLoading: true,
      errorMessage: null,
      searchQuery: '',
      selectedFilter: DevicesFilter.all,
      allDevices: <DeviceEntity>[],
      filteredDevices: <DeviceEntity>[],
    );
  }

  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;
  final DevicesFilter selectedFilter;
  final List<DeviceEntity> allDevices;
  final List<DeviceEntity> filteredDevices;

  DevicesState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
    DevicesFilter? selectedFilter,
    List<DeviceEntity>? allDevices,
    List<DeviceEntity>? filteredDevices,
    bool clearError = false,
  }) {
    return DevicesState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      allDevices: allDevices ?? this.allDevices,
      filteredDevices: filteredDevices ?? this.filteredDevices,
    );
  }
}
