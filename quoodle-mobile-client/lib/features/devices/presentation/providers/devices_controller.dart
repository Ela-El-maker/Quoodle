import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_state.dart';

class DevicesController extends AutoDisposeNotifier<DevicesState> {
  @override
  DevicesState build() {
    return DevicesState.initial();
  }

  Future<void> loadDevices() async {
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final devices = ref.read(getDevicesProvider).call();
    _emitWithFilters(allDevices: devices, isLoading: false);
  }

  void setSearchQuery(String query) {
    _emitWithFilters(searchQuery: query);
  }

  void clearSearch() {
    _emitWithFilters(searchQuery: '');
  }

  void setFilter(DevicesFilter filter) {
    _emitWithFilters(selectedFilter: filter);
  }

  void _emitWithFilters({
    List<DeviceEntity>? allDevices,
    String? searchQuery,
    DevicesFilter? selectedFilter,
    bool? isLoading,
  }) {
    final nextAllDevices = allDevices ?? state.allDevices;
    final nextQuery = searchQuery ?? state.searchQuery;
    final nextFilter = selectedFilter ?? state.selectedFilter;

    var filtered = nextAllDevices;

    if (nextQuery.isNotEmpty) {
      final needle = nextQuery.toLowerCase();
      filtered = filtered
          .where(
            (d) =>
                d.name.toLowerCase().contains(needle) ||
                d.id.toLowerCase().contains(needle) ||
                d.ipAddress.toLowerCase().contains(needle),
          )
          .toList();
    }

    if (nextFilter != DevicesFilter.all) {
      filtered = filtered.where((d) {
        switch (nextFilter) {
          case DevicesFilter.online:
            return d.status == DeviceStatusType.online;
          case DevicesFilter.offline:
            return d.status == DeviceStatusType.offline;
          case DevicesFilter.degraded:
            return d.status == DeviceStatusType.degraded;
          case DevicesFilter.all:
            return true;
        }
      }).toList();
    }

    state = state.copyWith(
      isLoading: isLoading ?? state.isLoading,
      allDevices: nextAllDevices,
      searchQuery: nextQuery,
      selectedFilter: nextFilter,
      filteredDevices: filtered,
    );
  }
}
