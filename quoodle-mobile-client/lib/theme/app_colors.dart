import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF7F8FA);
  static const Color backgroundAlt = Color(0xFFFBFCFD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceRaised = Color(0xFFF3F5F7);
  static const Color glass = Color(0xCCFFFFFF);
  static const Color glassBorder = Color(0xFFE7EBF0);
  static const Color glow = Color(0x147FA8C9);

  static const Color accentBlue = Color(0xFF7FA8C9);
  static const Color accentCyan = Color(0xFF7FA8C9);
  static const Color accentMint = Color(0xFF94B8A5);
  static const Color accentAmber = Color(0xFFD8B27C);
  static const Color accentRose = Color(0xFFC98E8A);

  static const Color compliant = Color(0xFF94B8A5);
  static const Color degraded = Color(0xFFD8B27C);
  static const Color nonCompliant = Color(0xFFC98E8A);
  static const Color quarantined = Color(0xFF9BB7C9);

  static const Color riskLow = Color(0xFF94B8A5);
  static const Color riskMedium = Color(0xFFD8B27C);
  static const Color riskHigh = Color(0xFFC69B87);
  static const Color riskCritical = Color(0xFFB97C85);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9AA3AF);

  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF9FAFB),
          Color(0xFFF5F7F9),
          Color(0xFFF7F8FA),
        ],
      );

  static LinearGradient get accentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF8FB3CF),
          Color(0xFF7FA8C9),
        ],
      );

  static LinearGradient get glassGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF8FAFC),
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
