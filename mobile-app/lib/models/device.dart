class Device {
  const Device({
    required this.deviceId,
    required this.deviceName,
    required this.lifecycleState,
    required this.lastSeen,
    required this.agentVersion,
    required this.osBuild,
    required this.complianceStatus,
    required this.riskScore,
  });

  final String deviceId;
  final String? deviceName;
  final String lifecycleState;
  final String? lastSeen;
  final String? agentVersion;
  final String? osBuild;
  final String? complianceStatus;
  final num? riskScore;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String?,
      lifecycleState: json['lifecycle_state'] as String? ?? 'unknown',
      lastSeen: json['last_seen'] as String?,
      agentVersion: json['agent_version'] as String?,
      osBuild: json['os_build'] as String?,
      complianceStatus: json['compliance_status'] as String?,
      riskScore: json['risk_score'] as num?,
    );
  }
}
