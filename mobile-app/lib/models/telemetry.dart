class TelemetrySnapshot {
  const TelemetrySnapshot({
    required this.deviceId,
    required this.timestamp,
    required this.cpu,
    required this.ram,
    required this.diskUsage,
    required this.networkTx,
    required this.networkRx,
    required this.riskScore,
  });

  final String deviceId;
  final String? timestamp;
  final String? cpu;
  final String? ram;
  final String? diskUsage;
  final String? networkTx;
  final String? networkRx;
  final num? riskScore;

  factory TelemetrySnapshot.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as Map<String, dynamic>? ?? {};
    return TelemetrySnapshot(
      deviceId: json['device_id'] as String,
      timestamp: json['timestamp'] as String?,
      cpu: metrics['cpu'] as String?,
      ram: metrics['ram'] as String?,
      diskUsage: metrics['disk_usage'] as String?,
      networkTx: metrics['network_tx'] as String?,
      networkRx: metrics['network_rx'] as String?,
      riskScore: metrics['risk_score'] as num?,
    );
  }
}

class TelemetryPoint {
  const TelemetryPoint({
    required this.timestamp,
    required this.avgCpu,
    required this.avgRam,
    required this.avgDiskUsage,
    required this.riskScoreAvg,
  });

  final String? timestamp;
  final num avgCpu;
  final num avgRam;
  final num avgDiskUsage;
  final num riskScoreAvg;

  factory TelemetryPoint.fromJson(Map<String, dynamic> json) {
    return TelemetryPoint(
      timestamp: json['timestamp'] as String?,
      avgCpu: json['avg_cpu'] as num? ?? 0,
      avgRam: json['avg_ram'] as num? ?? 0,
      avgDiskUsage: json['avg_disk_usage'] as num? ?? 0,
      riskScoreAvg: json['risk_score_avg'] as num? ?? 0,
    );
  }
}
