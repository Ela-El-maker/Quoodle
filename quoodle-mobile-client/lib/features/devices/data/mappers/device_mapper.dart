import 'package:secure_device_control/features/devices/data/dtos/device_dto.dart';
import 'package:secure_device_control/features/devices/domain/entities/device_entity.dart';

extension DeviceMapper on DeviceDto {
  DeviceEntity toDomain() {
    return DeviceEntity(
      id: id,
      name: name,
      status: _mapStatus(status),
      lastSeen: lastSeen,
      riskScore: riskScore,
      compliance: _mapCompliance(compliance),
      os: os,
      policySync: policySync,
      agentVersion: agentVersion,
      ipAddress: ipAddress,
      hostname: hostname,
      pairedAt: pairedAt,
      assignedUser: assignedUser,
      location: location,
    );
  }
}

DeviceStatusType _mapStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case 'online':
    case 'active':
      return DeviceStatusType.online;
    case 'offline':
      return DeviceStatusType.offline;
    case 'degraded':
    case 'stale':
    case 'reconnecting':
      return DeviceStatusType.degraded;
    case 'quarantined':
      return DeviceStatusType.quarantined;
    default:
      return DeviceStatusType.pending;
  }
}

DeviceComplianceType _mapCompliance(String compliance) {
  switch (compliance.trim().toLowerCase()) {
    case 'compliant':
      return DeviceComplianceType.compliant;
    case 'non_compliant':
    case 'non-compliant':
      return DeviceComplianceType.nonCompliant;
    default:
      return DeviceComplianceType.unknown;
  }
}
