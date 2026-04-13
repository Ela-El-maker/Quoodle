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
    final id = _asString(map['id'] ?? map['device_id']);
    final name = _asString(map['name'] ?? map['device_name']);
    final status = _asString(
      map['status'] ?? map['resolved_presence_state'] ?? map['lifecycle_state'],
    );
    final compliance = _asString(
      map['compliance'] ??
          map['resolved_compliance_status'] ??
          map['compliance_status'],
    );
    final lastSeenIso = _asString(map['last_seen']);

    return DeviceDto(
      id: id,
      name: name.isEmpty ? 'Unknown Device' : name,
      status: status.isEmpty ? 'pending' : status,
      lastSeen: _asString(map['lastSeen']).isNotEmpty
          ? _asString(map['lastSeen'])
          : _relativeLastSeen(lastSeenIso),
      riskScore: _toInt(map['riskScore'] ?? map['risk_score']) ?? 0,
      compliance: compliance.isEmpty ? 'unknown' : compliance,
      os: _asString(map['os'] ?? map['resolved_os_build'] ?? map['os_build'])
          .ifEmpty('Unknown'),
      policySync: _toBool(map['policySync'] ?? map['resolved_policy_in_sync']),
      agentVersion: _asString(map['agentVersion'] ?? map['agent_version'])
          .ifEmpty('0.0.0'),
      ipAddress: _asString(map['ipAddress']).ifEmpty('0.0.0.0'),
      hostname: _asString(map['hostname']).ifEmpty(name),
      pairedAt:
          _asString(map['pairedAt']).ifEmpty(lastSeenIso).ifEmpty('unknown'),
      assignedUser: _asString(map['assignedUser'] ?? map['owner_email'])
          .ifEmpty('Unassigned'),
      location: _asString(map['location']).ifEmpty('Unknown'),
    );
  }

  static String _asString(Object? value) {
    if (value is String) return value;
    if (value == null) return '';
    return value.toString();
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static String _relativeLastSeen(String isoString) {
    if (isoString.isEmpty) return 'unknown';
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return 'unknown';

    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

extension on String {
  String ifEmpty(String fallback) {
    return isEmpty ? fallback : this;
  }
}
