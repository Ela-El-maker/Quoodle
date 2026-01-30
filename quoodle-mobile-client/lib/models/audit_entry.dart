class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.eventType,
    required this.summary,
    required this.hash,
    required this.prevHash,
    required this.signature,
  });

  final String id;
  final String? timestamp;
  final String eventType;
  final String summary;
  final String? hash;
  final String? prevHash;
  final String? signature;

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>? ?? {};
    return AuditEntry(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] as String?,
      eventType: json['event_type'] as String? ?? 'event',
      summary: json['summary'] as String? ?? 'event',
      hash: details['hash'] as String?,
      prevHash: details['prev_hash'] as String?,
      signature: details['signature'] as String?,
    );
  }
}
