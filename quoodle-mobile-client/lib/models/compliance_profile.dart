class ComplianceProfile {
  const ComplianceProfile({
    required this.profileId,
    required this.description,
    required this.rules,
  });

  final String profileId;
  final String description;
  final List<dynamic> rules;

  factory ComplianceProfile.fromJson(Map<String, dynamic> json) {
    return ComplianceProfile(
      profileId: json['profile_id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rules: (json['rules'] as List<dynamic>? ?? const []),
    );
  }
}
