import 'dart:convert';

/// Represents the data encoded in a device pairing QR code.
///
/// QR codes follow the format:
/// ```json
/// {
///   "type": "quoodle_pair",
///   "version": 1,
///   "device_id": "PC-001-ABCD",
///   "pair_token": "abc123...",
///   "pair_session_id": "sess_xyz...",
///   "timestamp": "2026-01-13T12:00:00Z",
///   "controller_url": "https://api.example.com"
/// }
/// ```
class QrPairingData {
  const QrPairingData({
    required this.type,
    required this.version,
    required this.deviceId,
    required this.pairToken,
    this.pairSessionId,
    required this.timestamp,
    this.controllerUrl,
    this.deviceLabel,
  });

  /// Expected type identifier for pairing QR codes
  static const expectedType = 'quoodle_pair';

  /// Current supported version
  static const currentVersion = 1;

  final String type;
  final int version;
  final String deviceId;
  final String pairToken;
  final String? pairSessionId;
  final String timestamp;
  final String? controllerUrl;
  final String? deviceLabel;

  /// Parse QR code raw string data into structured pairing data.
  ///
  /// Throws [QrParseException] if the data is invalid.
  factory QrPairingData.fromRawString(String raw) {
    if (raw.isEmpty) {
      throw const QrParseException('Empty QR code data');
    }

    // Try to parse as JSON
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const QrParseException('QR code is not a JSON object');
      }
      json = decoded;
    } on FormatException catch (e) {
      throw QrParseException('Invalid JSON in QR code: ${e.message}');
    }

    return QrPairingData.fromJson(json);
  }

  /// Parse from decoded JSON map.
  factory QrPairingData.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw const QrParseException('Missing "type" field');
    }
    if (type != expectedType) {
      throw QrParseException(
          'Invalid QR type: expected "$expectedType", got "$type"');
    }

    final version = json['version'] as int?;
    if (version == null) {
      throw const QrParseException('Missing "version" field');
    }
    if (version > currentVersion) {
      throw QrParseException(
          'Unsupported QR version: $version (max supported: $currentVersion)');
    }

    final deviceId = json['device_id'] as String?;
    if (deviceId == null || deviceId.isEmpty) {
      throw const QrParseException('Missing "device_id" field');
    }

    final pairToken = json['pair_token'] as String?;
    if (pairToken == null || pairToken.isEmpty) {
      throw const QrParseException('Missing "pair_token" field');
    }

    final pairSessionId = json['pair_session_id'] as String?;

    final timestamp = json['timestamp'] as String?;
    if (timestamp == null || timestamp.isEmpty) {
      throw const QrParseException('Missing "timestamp" field');
    }

    // Validate timestamp is not too old (5 minute window)
    try {
      final ts = DateTime.parse(timestamp);
      final now = DateTime.now().toUtc();
      final age = now.difference(ts);
      if (age.inMinutes > 5) {
        throw QrParseException(
            'QR code expired: generated ${age.inMinutes} minutes ago');
      }
      if (age.inMinutes < -1) {
        throw const QrParseException('QR code timestamp is in the future');
      }
    } on FormatException {
      throw const QrParseException('Invalid timestamp format');
    }

    return QrPairingData(
      type: type,
      version: version,
      deviceId: deviceId,
      pairToken: pairToken,
      pairSessionId: pairSessionId,
      timestamp: timestamp,
      controllerUrl: json['controller_url'] as String?,
      deviceLabel: json['device_label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'device_id': deviceId,
        'pair_token': pairToken,
        if (pairSessionId != null) 'pair_session_id': pairSessionId,
        'timestamp': timestamp,
        if (controllerUrl != null) 'controller_url': controllerUrl,
        if (deviceLabel != null) 'device_label': deviceLabel,
      };

  @override
  String toString() =>
      'QrPairingData(deviceId: $deviceId, pairSessionId: $pairSessionId)';
}

/// Exception thrown when QR code parsing fails.
class QrParseException implements Exception {
  const QrParseException(this.message);

  final String message;

  @override
  String toString() => 'QrParseException: $message';
}
