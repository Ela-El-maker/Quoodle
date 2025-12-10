class CommandState {
  const CommandState({
    required this.commandId,
    required this.deviceId,
    required this.method,
    required this.state,
    required this.queuedAt,
    this.completedAt,
    this.resultStatus,
    this.errorCode,
    this.errorMessage,
  });

  final String? commandId;
  final String? deviceId;
  final String? method;
  final String? state;
  final String? queuedAt;
  final String? completedAt;
  final String? resultStatus;
  final int? errorCode;
  final String? errorMessage;

  factory CommandState.fromJson(Map<String, dynamic> json) {
    return CommandState(
      commandId: json['command_id'] as String?,
      deviceId: json['device_id'] as String?,
      method: json['method'] as String?,
      state: json['state'] as String?,
      queuedAt: json['queued_at'] as String?,
      completedAt: json['completed_at'] as String?,
      resultStatus: (json['result'] as Map<String, dynamic>?)?['status'] as String? ?? json['result_status'] as String?,
      errorCode: json['error_code'] as int?,
      errorMessage: json['error_message'] as String?,
    );
  }
}
