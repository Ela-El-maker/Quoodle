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
    this.serverSeq,
    this.requestSig,
    this.envelopeSig,
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
  final int? serverSeq;
  final String? requestSig;
  final String? envelopeSig;

  factory CommandState.fromJson(Map<String, dynamic> json) {
    final audit = json['audit'] as Map<String, dynamic>?;
    return CommandState(
      commandId: json['command_id'] as String?,
      deviceId: json['device_id'] as String?,
      method: json['method'] as String?,
      state: json['state'] as String?,
      queuedAt: json['queued_at'] as String?,
      completedAt: json['completed_at'] as String?,
      resultStatus:
          (json['result'] as Map<String, dynamic>?)?['status'] as String? ??
              json['result_status'] as String?,
      errorCode: json['error_code'] as int?,
      errorMessage: json['error_message'] as String?,
      serverSeq: (audit?['server_seq'] as num?)?.toInt(),
      requestSig: audit?['request_sig'] as String?,
      envelopeSig: audit?['envelope_sig'] as String?,
    );
  }
}
