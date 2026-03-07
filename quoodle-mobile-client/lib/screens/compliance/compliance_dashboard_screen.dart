import 'package:flutter/material.dart';

import '../../models/compliance_profile.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';

class ComplianceDashboardScreen extends StatefulWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  State<ComplianceDashboardScreen> createState() =>
      _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState extends State<ComplianceDashboardScreen> {
  final ApiService _api = ApiService();
  late Future<List<ComplianceProfile>> _profiles;

  @override
  void initState() {
    super.initState();
    _profiles = _api.fetchComplianceProfiles();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
      child: FutureBuilder<List<ComplianceProfile>>(
        future: _profiles,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profiles = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Compliance dashboard',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Review policy profiles and recent compliance decisions.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Policy profiles',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (profiles.isEmpty)
                Text(
                  'No profiles available',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                )
              else
                ...profiles.map((profile) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.profileId,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 6),
                            Text(
                              profile.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Rules: ${profile.rules.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Remediation queue',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Track devices with attestation failures or quarantine triggers.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No remediation items found.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
