enum DeviceStatusType { online, offline, degraded, quarantined, pending }

enum DeviceComplianceType { compliant, nonCompliant, unknown }

class DeviceEntity {
  const DeviceEntity({
    required this.id,
    required this.name,
    required this.status,
    required this.lastSeen,
    required this.riskScore,
    required this.compliance,
    required this.os,
    required this.policySync,
    required this.agentVersion,
    required this.ipAddress,
    required this.hostname,
    required this.pairedAt,
    required this.assignedUser,
    required this.location,
  });

  final String id;
  final String name;
  final DeviceStatusType status;
  final String lastSeen;
  final int riskScore;
  final DeviceComplianceType compliance;
  final String os;
  final bool policySync;
  final String agentVersion;
  final String ipAddress;
  final String hostname;
  final String pairedAt;
  final String assignedUser;
  final String location;
}
