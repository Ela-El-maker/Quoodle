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
    required this.policyHash,
    required this.reportedPolicyHash,
    required this.policyInSync,
  });

  final String deviceId;
  final String? deviceName;
  final String lifecycleState;
  final String? lastSeen;
  final String? agentVersion;
  final String? osBuild;
  final String? complianceStatus;
  final num? riskScore;
  final String? policyHash;
  final String? reportedPolicyHash;
  final bool? policyInSync;

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
      policyHash: json['policy_hash'] as String?,
      reportedPolicyHash: json['reported_policy_hash'] as String?,
      policyInSync: json['policy_in_sync'] as bool?,
    );
  }
}
