class UpdateStatus {
  const UpdateStatus({
    required this.releaseId,
    required this.version,
    required this.status,
    required this.lastUpdateAt,
    this.phase,
    this.progressPercent,
    this.progressDetail,
    this.errorCode,
    this.errorMessage,
  });

  final String? releaseId;
  final String? version;
  final String? status;
  final String? lastUpdateAt;
  final String? phase;
  final int? progressPercent;
  final String? progressDetail;
  final int? errorCode;
  final String? errorMessage;

  factory UpdateStatus.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? {};
    return UpdateStatus(
      releaseId: json['release_id'] as String?,
      version: json['version'] as String?,
      status: json['status'] as String? ?? json['phase'] as String?,
      lastUpdateAt: json['last_update_at'] as String?,
      phase: json['phase'] as String?,
      progressPercent: progress['percent'] as int? ?? json['progress_percent'] as int?,
      progressDetail: progress['detail'] as String? ?? json['progress_detail'] as String?,
      errorCode: json['error_code'] as int?,
      errorMessage: json['error_message'] as String?,
    );
  }
}
