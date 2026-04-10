import 'dart:convert';

class QrParseException implements Exception {
  const QrParseException(this.message);

  final String message;

  @override
  String toString() => 'QrParseException: $message';
}

class QrPairingData {
  const QrPairingData({
    required this.type,
    required this.version,
    required this.deviceId,
    required this.pairToken,
    required this.pairSessionId,
    required this.timestamp,
    this.controllerUrl,
    this.deviceLabel,
  });

  static const String expectedType = 'quoodle_pair';
  static const int supportedVersion = 1;
  static const Duration maxAge = Duration(minutes: 5);
  static const Duration maxFutureSkew = Duration(minutes: 1);

  final String type;
  final int version;
  final String deviceId;
  final String pairToken;
  final String pairSessionId;
  final String timestamp;
  final String? controllerUrl;
  final String? deviceLabel;

  static QrPairingData fromRawString(String raw) {
    if (raw.trim().isEmpty) {
      throw const QrParseException('QR content is empty');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const QrParseException('QR content is not valid JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const QrParseException('QR content must be a JSON object');
    }

    return fromJson(decoded);
  }

  static QrPairingData fromJson(Map<String, dynamic> json) {
    final type = _requiredString(json, 'type');
    if (type != expectedType) {
      throw QrParseException('Invalid QR type: $type');
    }

    final versionRaw = json['version'];
    final version =
        versionRaw is int ? versionRaw : int.tryParse('$versionRaw');
    if (version == null || version != supportedVersion) {
      throw QrParseException('Unsupported QR version: $versionRaw');
    }

    final deviceId = _requiredString(json, 'device_id');
    final pairToken = _requiredString(json, 'pair_token');
    final pairSessionId = _requiredString(json, 'pair_session_id');
    final timestamp = _requiredString(json, 'timestamp');

    _validateTimestamp(timestamp);

    return QrPairingData(
      type: type,
      version: version,
      deviceId: deviceId,
      pairToken: pairToken,
      pairSessionId: pairSessionId,
      timestamp: timestamp,
      controllerUrl: json['controller_url']?.toString(),
      deviceLabel: json['device_label']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'version': version,
      'device_id': deviceId,
      'pair_token': pairToken,
      'pair_session_id': pairSessionId,
      'timestamp': timestamp,
      if (controllerUrl != null) 'controller_url': controllerUrl,
      if (deviceLabel != null) 'device_label': deviceLabel,
    };
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString();
    if (value == null || value.trim().isEmpty) {
      throw QrParseException('Missing required field: $key');
    }
    return value;
  }

  static void _validateTimestamp(String rawTimestamp) {
    final parsed = DateTime.tryParse(rawTimestamp)?.toUtc();
    if (parsed == null) {
      throw const QrParseException('Invalid timestamp format');
    }

    final now = DateTime.now().toUtc();
    if (parsed.isAfter(now.add(maxFutureSkew))) {
      throw const QrParseException('QR timestamp is in the future');
    }

    if (parsed.isBefore(now.subtract(maxAge))) {
      throw const QrParseException('QR code has expired');
    }
  }

  @override
  String toString() {
    return 'QrPairingData(deviceId: $deviceId, pairSessionId: $pairSessionId, version: $version)';
  }
}
