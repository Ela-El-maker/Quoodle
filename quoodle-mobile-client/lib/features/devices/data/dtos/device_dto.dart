class DeviceDto {
  const DeviceDto({
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
  final String status;
  final String lastSeen;
  final int riskScore;
  final String compliance;
  final String os;
  final bool policySync;
  final String agentVersion;
  final String ipAddress;
  final String hostname;
  final String pairedAt;
  final String assignedUser;
  final String location;

  factory DeviceDto.fromMap(Map<String, dynamic> map) {
    return DeviceDto(
      id: map['id'] as String,
      name: map['name'] as String,
      status: map['status'] as String? ?? 'pending',
      lastSeen: map['lastSeen'] as String? ?? 'unknown',
      riskScore: (map['riskScore'] as int?) ?? 0,
      compliance: map['compliance'] as String? ?? 'unknown',
      os: map['os'] as String? ?? 'Unknown',
      policySync: (map['policySync'] as bool?) ?? false,
      agentVersion: map['agentVersion'] as String? ?? '0.0.0',
      ipAddress: map['ipAddress'] as String? ?? '0.0.0.0',
      hostname: map['hostname'] as String? ?? (map['name'] as String? ?? ''),
      pairedAt: map['pairedAt'] as String? ?? '2026-01-14T09:22:00Z',
      assignedUser: map['assignedUser'] as String? ?? 'Unassigned',
      location: map['location'] as String? ?? 'Unknown',
    );
  }
}
