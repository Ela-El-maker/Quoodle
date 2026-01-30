import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0B0F1A);
  static const Color backgroundAlt = Color(0xFF0F1729);
  static const Color surface = Color(0xFF151C2F);
  static const Color surfaceRaised = Color(0xFF1B2540);
  static const Color glass = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x55FFFFFF);
  static const Color glow = Color(0xFF3FA9F5);

  static const Color accentBlue = Color(0xFF3FA9F5);
  static const Color accentCyan = Color(0xFF00D4FF);
  static const Color accentMint = Color(0xFF00D8A5);
  static const Color accentAmber = Color(0xFFFFC857);
  static const Color accentRose = Color(0xFFFF5C7C);

  static const Color compliant = Color(0xFF24D6A1);
  static const Color degraded = Color(0xFFFFC857);
  static const Color nonCompliant = Color(0xFFFF6B6B);
  static const Color quarantined = Color(0xFF6AB7FF);

  static const Color riskLow = Color(0xFF2DD4BF);
  static const Color riskMedium = Color(0xFFFFC857);
  static const Color riskHigh = Color(0xFFFF8A5B);
  static const Color riskCritical = Color(0xFFFF5C7C);

  static const Color textPrimary = Color(0xFFE6ECF8);
  static const Color textSecondary = Color(0xFF9FB0D8);
  static const Color textMuted = Color(0xFF6D7AA6);

  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0B0F1A),
          Color(0xFF0F1B2E),
          Color(0xFF0B0F1A),
        ],
      );

  static LinearGradient get accentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF3FA9F5),
          Color(0xFF00D4FF),
        ],
      );

  static LinearGradient get glassGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x55FFFFFF),
          Color(0x11FFFFFF),
        ],
      );

  static Color complianceColor(String? status) {
    final value = (status ?? '').toLowerCase();
    if (value.contains('quarantine')) return quarantined;
    if (value.contains('degrad')) return degraded;
    if (value.contains('non') || value.contains('fail')) return nonCompliant;
    if (value.contains('compliant') || value.contains('ok')) return compliant;
    return textMuted;
  }

  static String complianceLabel(String? status) {
    final value = (status ?? '').toLowerCase();
    if (value.contains('quarantine')) return 'Quarantined';
    if (value.contains('degrad')) return 'Degraded';
    if (value.contains('non') || value.contains('fail')) return 'Non-compliant';
    if (value.contains('compliant') || value.contains('ok')) return 'Compliant';
    return 'Unknown';
  }

  static Color riskColor(num? score) {
    if (score == null) return textMuted;
    if (score >= 80) return riskCritical;
    if (score >= 60) return riskHigh;
    if (score >= 35) return riskMedium;
    return riskLow;
  }
}
