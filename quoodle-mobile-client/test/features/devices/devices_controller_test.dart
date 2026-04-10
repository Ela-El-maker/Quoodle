import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';
import 'package:secure_device_control/features/devices/domain/repositories/devices_repository.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_state.dart';

class _FakeDevicesRepository implements DevicesRepository {
  _FakeDevicesRepository(this._devices);

  final List<DeviceEntity> _devices;

  @override
  List<DeviceEntity> getDevices() {
    return List<DeviceEntity>.unmodifiable(_devices);
  }

  @override
  DeviceEntity? getDeviceById(String id) {
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }
}

void main() {
  group('DevicesController', () {
    test('loads devices and applies search/filter', () async {
      final fakeRepository = _FakeDevicesRepository([
        const DeviceEntity(
          id: 'dev-001',
          name: 'PROD-SRV-001',
          status: DeviceStatusType.online,
          lastSeen: '2s ago',
          riskScore: 12,
          compliance: DeviceComplianceType.compliant,
          os: 'Ubuntu 22.04',
          policySync: true,
          agentVersion: '2.1.4',
          ipAddress: '10.0.1.11',
          hostname: 'PRODSRV001',
          pairedAt: '2026-01-11T08:10:00Z',
          assignedUser: 'Ops Bot',
          location: 'Tokyo DC - Rack A3',
        ),
        const DeviceEntity(
          id: 'dev-007',
          name: 'WKS-FINANCE-07',
          status: DeviceStatusType.degraded,
          lastSeen: '12s ago',
          riskScore: 71,
          compliance: DeviceComplianceType.nonCompliant,
          os: 'Windows 10 Pro',
          policySync: false,
          agentVersion: '2.0.9',
          ipAddress: '10.0.3.22',
          hostname: 'WKSFINANCE07',
          pairedAt: '2026-01-14T09:22:00Z',
          assignedUser: 'L. Nakamura',
          location: 'Tokyo HQ - Floor 3',
        ),
        const DeviceEntity(
          id: 'dev-014',
          name: 'PROD-SRV-014',
          status: DeviceStatusType.offline,
          lastSeen: '18m ago',
          riskScore: 94,
          compliance: DeviceComplianceType.unknown,
          os: 'Ubuntu 20.04',
          policySync: false,
          agentVersion: '2.0.7',
          ipAddress: '10.0.1.14',
          hostname: 'PRODSRV014',
          pairedAt: '2026-01-05T03:05:00Z',
          assignedUser: 'Ops Bot',
          location: 'Tokyo DC - Rack B2',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          devicesRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      final sub = container.listen(
        devicesControllerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(container.dispose);
      addTearDown(sub.close);

      await container.read(devicesControllerProvider.notifier).loadDevices();

      expect(container.read(devicesControllerProvider).allDevices.length, 3);

      container.read(devicesControllerProvider.notifier).setSearchQuery('fin');
      expect(
        container.read(devicesControllerProvider).filteredDevices.single.id,
        'dev-007',
      );

      container.read(devicesControllerProvider.notifier).clearSearch();
      container
          .read(devicesControllerProvider.notifier)
          .setFilter(DevicesFilter.offline);
      expect(
        container.read(devicesControllerProvider).filteredDevices.single.id,
        'dev-014',
      );

      expect(
        container.read(deviceDetailProvider('dev-001'))?.name,
        'PROD-SRV-001',
      );
    });
  });
}
