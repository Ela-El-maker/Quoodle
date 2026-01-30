class CommandState {
  const CommandState({
    required this.commandId,
    required this.deviceId,
    required this.method,
    required this.state,
    required this.queuedAt,
    this.completedAt,
    this.params,
    this.resultStatus,
    this.resultNotes,
    this.artifactUrl,
    this.artifactChecksum,
    this.resultData,
    this.errorCode,
    this.errorMessage,
    this.serverSeq,
    this.requestSig,
    this.envelopeSig,
    this.envelope,
  });

  final String? commandId;
  final String? deviceId;
  final String? method;
  final String? state;
  final String? queuedAt;
  final String? completedAt;
  final Map<String, dynamic>? params;
  final String? resultStatus;
  final String? resultNotes;
  final String? artifactUrl;
  final String? artifactChecksum;
  final Map<String, dynamic>? resultData;
  final int? errorCode;
  final String? errorMessage;
  final int? serverSeq;
  final String? requestSig;
  final String? envelopeSig;
  final Map<String, dynamic>? envelope;

  factory CommandState.fromJson(Map<String, dynamic> json) {
    final audit = json['audit'] as Map<String, dynamic>?;
    final rawResult = json['result'];
    final result =
        rawResult is Map<String, dynamic> ? rawResult : <String, dynamic>{};
    final rawParams = json['params'];
    final params =
        rawParams is Map<String, dynamic> ? rawParams : <String, dynamic>{};
    final rawResultData = result['data'];
    final resultData = rawResultData is Map<String, dynamic>
        ? rawResultData
        : <String, dynamic>{};
    return CommandState(
      commandId: json['command_id'] as String?,
      deviceId: json['device_id'] as String?,
      method: json['method'] as String?,
      state: json['state'] as String?,
      queuedAt: json['queued_at'] as String?,
      completedAt: json['completed_at'] as String?,
      params: params,
      resultStatus: result['status'] as String? ?? json['result_status'] as String?,
      resultNotes: result['notes'] as String?,
      artifactUrl: result['artifact_url'] as String?,
      artifactChecksum: result['artifact_checksum'] as String?,
      resultData: resultData,
      errorCode: json['error_code'] as int?,
      errorMessage: json['error_message'] as String?,
      serverSeq: (audit?['server_seq'] as num?)?.toInt(),
      requestSig: audit?['request_sig'] as String?,
      envelopeSig: audit?['envelope_sig'] as String?,
      envelope: audit?['envelope'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command_id': commandId,
      'device_id': deviceId,
      'method': method,
      'state': state,
      'queued_at': queuedAt,
      'completed_at': completedAt,
      'params': params,
      'result_status': resultStatus,
      'result': {
        'status': resultStatus,
        'notes': resultNotes,
        'artifact_url': artifactUrl,
        'artifact_checksum': artifactChecksum,
        'data': resultData,
      },
      'error_code': errorCode,
      'error_message': errorMessage,
      'audit': {
        'server_seq': serverSeq,
        'request_sig': requestSig,
        'envelope_sig': envelopeSig,
        'envelope': envelope,
      },
    };
  }
}
