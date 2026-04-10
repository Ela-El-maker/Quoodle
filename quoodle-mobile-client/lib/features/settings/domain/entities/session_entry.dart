class SessionEntry {
  const SessionEntry({
    required this.id,
    required this.device,
    required this.location,
    required this.ip,
    required this.lastActive,
    required this.isCurrent,
  });

  final String id;
  final String device;
  final String location;
  final String ip;
  final DateTime lastActive;
  final bool isCurrent;
}
