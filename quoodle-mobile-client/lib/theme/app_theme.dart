import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Core Palette ──────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF00D4FF);
  static const Color primaryMuted = Color(0x4D00D4FF);
  static const Color primaryDim = Color(0x1A00D4FF);
  static const Color secondary = Color(0xFF10B981);
  static const Color secondaryMuted = Color(0x3310B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningMuted = Color(0x33F59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorMuted = Color(0x33EF4444);
  static const Color critical = Color(0xFFFF3B3B);
  static const Color criticalMuted = Color(0x33FF3B3B);

  // ── Surface System ─────────────────────────────────────────────────────────
  static const Color background = Color(0xFF080E17);
  static const Color surface = Color(0xFF0F1923);
  static const Color surfaceVariant = Color(0xFF1A2535);
  static const Color surfaceElevated = Color(0xFF1F2E42);
  static const Color glassSurface = Color(0xBF1A2535); // 75% opacity
  static const Color glassLight = Color(0x261A2535); // 15% opacity
  static const Color border = Color(0xFF2A3A52);
  static const Color borderLight = Color(0xFF1E2D42);

  // ── Text Colors ────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F4F8);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF4A5568);
  static const Color textDisabled = Color(0xFF2D3748);

  // ── Status Colors ──────────────────────────────────────────────────────────
  static const Color statusOnline = Color(0xFF10B981);
  static const Color statusOffline = Color(0xFF4A5568);
  static const Color statusDegraded = Color(0xFFF59E0B);
  static const Color statusQuarantined = Color(0xFFEF4444);
  static const Color statusPending = Color(0xFF00D4FF);

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFF000000),
        primaryContainer: primaryDim,
        onPrimaryContainer: primary,
        secondary: secondary,
        onSecondary: Color(0xFF000000),
        secondaryContainer: secondaryMuted,
        onSecondaryContainer: secondary,
        error: error,
        onError: Color(0xFFFFFFFF),
        errorContainer: errorMuted,
        onErrorContainer: error,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceVariant,
        onSurfaceVariant: textSecondary,
        outline: border,
        outlineVariant: borderLight,
        inverseSurface: textPrimary,
        onInverseSurface: surface,
        shadow: Color(0xFF000000),
        scrim: Color(0x80000000),
      ),
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.ibmPlexSans(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.ibmPlexSans(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineLarge: GoogleFonts.ibmPlexSans(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.ibmPlexSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: GoogleFonts.ibmPlexSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.ibmPlexSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        titleSmall: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        bodyLarge: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textMuted,
        ),
        labelLarge: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.2,
        ),
        labelMedium: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textSecondary,
          letterSpacing: 0.5,
        ),
        labelSmall: GoogleFonts.ibmPlexSans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textMuted,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        actionsIconTheme: const IconThemeData(color: textSecondary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: glassLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textMuted,
        ),
        hintStyle: GoogleFonts.ibmPlexSans(fontSize: 14, color: textMuted),
        errorStyle: GoogleFonts.ibmPlexSans(fontSize: 11, color: error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        selectedColor: primaryDim,
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceVariant,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        dividerColor: borderLight,
      ),
    );
  }

  static ThemeData get lightTheme {
    // Light theme — same structure, inverted surfaces
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF0F4F8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0066CC),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF10B981),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1A2535),
        surfaceContainerHighest: Color(0xFFE8EEF5),
        outline: Color(0xFFCBD5E1),
      ),
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme),
    );
  }
}
