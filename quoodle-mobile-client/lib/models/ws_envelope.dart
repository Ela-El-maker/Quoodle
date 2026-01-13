import 'dart:convert';

/// Types of WebSocket messages in the protocol.
enum WsMessageType {
  auth('AUTH'),
  authAck('AUTH_ACK'),
  authError('AUTH_ERROR'),
  heartbeat('HEARTBEAT'),
  telemetry('TELEMETRY'),
  commandDelivery('COMMAND_DELIVERY'),
  commandAck('COMMAND_ACK'),
  commandResult('COMMAND_RESULT'),
  alert('ALERT'),
  update('UPDATE'),
  unknown('UNKNOWN');

  const WsMessageType(this.value);
  final String value;

  static WsMessageType fromString(String? value) {
    if (value == null) return WsMessageType.unknown;
    for (final type in WsMessageType.values) {
      if (type.value == value) return type;
    }
    return WsMessageType.unknown;
  }
}

/// The common envelope format for all WebSocket messages.
class WsEnvelope {
  const WsEnvelope({
    required this.messageId,
    required this.timestamp,
    required this.type,
    required this.from,
    required this.deviceId,
    required this.body,
    required this.sig,
    this.sessionId,
  });

  final String messageId;
  final String timestamp;
  final WsMessageType type;
  final String from;
  final String deviceId;
  final String? sessionId;
  final Map<String, dynamic> body;
  final String sig;

  factory WsEnvelope.fromJson(Map<String, dynamic> json) {
    return WsEnvelope(
      messageId: json['message_id'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      type: WsMessageType.fromString(json['type'] as String?),
      from: json['from'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      body: (json['body'] as Map<String, dynamic>?) ?? {},
      sig: json['sig'] as String? ?? '',
    );
  }

  factory WsEnvelope.parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WsEnvelope.fromJson(json);
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'timestamp': timestamp,
      'type': type.value,
      'from': from,
      'device_id': deviceId,
      'session_id': sessionId,
      'body': body,
      'sig': sig,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  /// Checks if the envelope has required fields for a valid message.
  bool get isValid =>
      messageId.isNotEmpty &&
      timestamp.isNotEmpty &&
      type != WsMessageType.unknown &&
      from.isNotEmpty &&
      sig.isNotEmpty;

  @override
  String toString() => 'WsEnvelope(type: ${type.value}, from: $from, '
      'deviceId: $deviceId, sessionId: $sessionId)';
}

/// Auth acknowledgment body content.
class AuthAckBody {
  const AuthAckBody({
    required this.status,
    required this.sessionId,
    required this.heartbeatIntervalSeconds,
    required this.telemetryIntervalSeconds,
    this.policyHash,
  });

  final String status;
  final String sessionId;
  final int heartbeatIntervalSeconds;
  final int telemetryIntervalSeconds;
  final String? policyHash;

  factory AuthAckBody.fromJson(Map<String, dynamic> json) {
    return AuthAckBody(
      status: json['status'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      heartbeatIntervalSeconds:
          (json['heartbeat_interval_seconds'] as num?)?.toInt() ?? 30,
      telemetryIntervalSeconds:
          (json['telemetry_interval_seconds'] as num?)?.toInt() ?? 60,
      policyHash: json['policy_hash'] as String?,
    );
  }

  bool get isOk => status == 'ok';
}

/// Auth error body content.
class AuthErrorBody {
  const AuthErrorBody({
    required this.status,
    required this.errorCode,
    required this.errorMessage,
  });

  final String status;
  final String errorCode;
  final String errorMessage;

  factory AuthErrorBody.fromJson(Map<String, dynamic> json) {
    return AuthErrorBody(
      status: json['status'] as String? ?? 'error',
      errorCode: json['error_code'] as String? ?? 'UNKNOWN',
      errorMessage: json['error_message'] as String? ?? '',
    );
  }
}

/// Command delivery body content (command from server).
class CommandDeliveryBody {
  const CommandDeliveryBody({
    required this.commandMessageId,
    required this.method,
    required this.params,
    required this.priority,
    required this.ttlSeconds,
    required this.requiresAck,
  });

  final String commandMessageId;
  final String method;
  final Map<String, dynamic> params;
  final String priority;
  final int ttlSeconds;
  final bool requiresAck;

  factory CommandDeliveryBody.fromJson(Map<String, dynamic> json) {
    return CommandDeliveryBody(
      commandMessageId: json['command_message_id'] as String? ?? '',
      method: json['method'] as String? ?? '',
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      priority: json['priority'] as String? ?? 'normal',
      ttlSeconds: (json['ttl_seconds'] as num?)?.toInt() ?? 300,
      requiresAck: json['requires_ack'] as bool? ?? true,
    );
  }
}

/// Alert body content.
class AlertBody {
  const AlertBody({
    required this.alertId,
    required this.severity,
    required this.category,
    required this.message,
    required this.timestamp,
  });

  final String alertId;
  final String severity;
  final String category;
  final String message;
  final String timestamp;

  factory AlertBody.fromJson(Map<String, dynamic> json) {
    return AlertBody(
      alertId: json['alert_id'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      category: json['category'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

/// Update notification body content.
class UpdateBody {
  const UpdateBody({
    required this.updateType,
    required this.resourceId,
    required this.resourceType,
    this.data,
  });

  final String updateType;
  final String resourceId;
  final String resourceType;
  final Map<String, dynamic>? data;

  factory UpdateBody.fromJson(Map<String, dynamic> json) {
    return UpdateBody(
      updateType: json['update_type'] as String? ?? '',
      resourceId: json['resource_id'] as String? ?? '',
      resourceType: json['resource_type'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}
