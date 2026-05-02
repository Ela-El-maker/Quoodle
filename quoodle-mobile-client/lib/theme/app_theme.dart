import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class _ThemePalette {
  const _ThemePalette({
    required this.primary,
    required this.primaryMuted,
    required this.primaryDim,
    required this.secondary,
    required this.secondaryMuted,
    required this.warning,
    required this.warningMuted,
    required this.error,
    required this.errorMuted,
    required this.critical,
    required this.criticalMuted,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.glassSurface,
    required this.glassLight,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.statusOnline,
    required this.statusOffline,
    required this.statusDegraded,
    required this.statusQuarantined,
    required this.statusPending,
  });

  final Color primary;
  final Color primaryMuted;
  final Color primaryDim;
  final Color secondary;
  final Color secondaryMuted;
  final Color warning;
  final Color warningMuted;
  final Color error;
  final Color errorMuted;
  final Color critical;
  final Color criticalMuted;

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color surfaceElevated;
  final Color glassSurface;
  final Color glassLight;
  final Color border;
  final Color borderLight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  final Color statusOnline;
  final Color statusOffline;
  final Color statusDegraded;
  final Color statusQuarantined;
  final Color statusPending;
}

class AppTheme {
  static const _ThemePalette _dark = _ThemePalette(
    primary: Color(0xFF00D4FF),
    primaryMuted: Color(0x4D00D4FF),
    primaryDim: Color(0x1A00D4FF),
    secondary: Color(0xFF10B981),
    secondaryMuted: Color(0x3310B981),
    warning: Color(0xFFF59E0B),
    warningMuted: Color(0x33F59E0B),
    error: Color(0xFFEF4444),
    errorMuted: Color(0x33EF4444),
    critical: Color(0xFFFF3B3B),
    criticalMuted: Color(0x33FF3B3B),
    background: Color(0xFF0B0D10),
    surface: Color(0xFF12161B),
    surfaceVariant: Color(0xFF181D23),
    surfaceElevated: Color(0xFF1E242C),
    glassSurface: Color(0xCC12161B),
    glassLight: Color(0x2012161B),
    border: Color(0xFF252B33),
    borderLight: Color(0xFF1C2128),
    textPrimary: Color(0xFFF3F5F7),
    textSecondary: Color(0xFFA7B0BB),
    textMuted: Color(0xFF7E8792),
    textDisabled: Color(0xFF3D4550),
    statusOnline: Color(0xFF10B981),
    statusOffline: Color(0xFF4A5568),
    statusDegraded: Color(0xFFF59E0B),
    statusQuarantined: Color(0xFFEF4444),
    statusPending: Color(0xFF00D4FF),
  );

  static const _ThemePalette _light = _ThemePalette(
    primary: Color(0xFF0077C8),
    primaryMuted: Color(0x330077C8),
    primaryDim: Color(0x1A0077C8),
    secondary: Color(0xFF0B8F63),
    secondaryMuted: Color(0x330B8F63),
    warning: Color(0xFFB76B00),
    warningMuted: Color(0x33B76B00),
    error: Color(0xFFD12F2F),
    errorMuted: Color(0x33D12F2F),
    critical: Color(0xFFC22626),
    criticalMuted: Color(0x33C22626),
    background: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF0F3F7),
    surfaceElevated: Color(0xFFFFFFFF),
    glassSurface: Color(0xE6FFFFFF),
    glassLight: Color(0x99FFFFFF),
    border: Color(0xFFD8E0EA),
    borderLight: Color(0xFFE6ECF3),
    textPrimary: Color(0xFF12161B),
    textSecondary: Color(0xFF495463),
    textMuted: Color(0xFF687484),
    textDisabled: Color(0xFF9AA4B2),
    statusOnline: Color(0xFF0B8F63),
    statusOffline: Color(0xFF6B7280),
    statusDegraded: Color(0xFFB76B00),
    statusQuarantined: Color(0xFFD12F2F),
    statusPending: Color(0xFF0077C8),
  );

  static _ThemePalette _active = _dark;

  static void useBrightness(Brightness brightness) {
    _active = brightness == Brightness.dark ? _dark : _light;
  }

  static Color get primary => _active.primary;
  static Color get primaryMuted => _active.primaryMuted;
  static Color get primaryDim => _active.primaryDim;
  static Color get secondary => _active.secondary;
  static Color get secondaryMuted => _active.secondaryMuted;
  static Color get warning => _active.warning;
  static Color get warningMuted => _active.warningMuted;
  static Color get error => _active.error;
  static Color get errorMuted => _active.errorMuted;
  static Color get critical => _active.critical;
  static Color get criticalMuted => _active.criticalMuted;

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfaceVariant => _active.surfaceVariant;
  static Color get surfaceElevated => _active.surfaceElevated;
  static Color get glassSurface => _active.glassSurface;
  static Color get glassLight => _active.glassLight;
  static Color get border => _active.border;
  static Color get borderLight => _active.borderLight;

  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textMuted => _active.textMuted;
  static Color get textDisabled => _active.textDisabled;

  static Color get statusOnline => _active.statusOnline;
  static Color get statusOffline => _active.statusOffline;
  static Color get statusDegraded => _active.statusDegraded;
  static Color get statusQuarantined => _active.statusQuarantined;
  static Color get statusPending => _active.statusPending;

  static ThemeData get darkTheme => _buildTheme(_dark, Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(_light, Brightness.light);

  static ThemeData _buildTheme(_ThemePalette p, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
        secondary: p.secondary,
        onSecondary:
            brightness == Brightness.dark ? Colors.black : Colors.white,
        error: p.error,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
      ),
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.ibmPlexSans(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
            letterSpacing: -0.3),
        displayMedium: GoogleFonts.ibmPlexSans(
            fontSize: 28, fontWeight: FontWeight.w600, color: p.textPrimary),
        headlineLarge: GoogleFonts.ibmPlexSans(
            fontSize: 22, fontWeight: FontWeight.w600, color: p.textPrimary),
        headlineMedium: GoogleFonts.ibmPlexSans(
            fontSize: 22, fontWeight: FontWeight.w600, color: p.textPrimary),
        headlineSmall: GoogleFonts.ibmPlexSans(
            fontSize: 18, fontWeight: FontWeight.w600, color: p.textPrimary),
        titleLarge: GoogleFonts.ibmPlexSans(
            fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary),
        titleMedium: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
            letterSpacing: 0.1),
        titleSmall: GoogleFonts.ibmPlexSans(
            fontSize: 14, fontWeight: FontWeight.w400, color: p.textSecondary),
        bodyLarge: GoogleFonts.ibmPlexSans(
            fontSize: 16, fontWeight: FontWeight.w400, color: p.textPrimary),
        bodyMedium: GoogleFonts.ibmPlexSans(
            fontSize: 14, fontWeight: FontWeight.w400, color: p.textSecondary),
        bodySmall: GoogleFonts.ibmPlexSans(
            fontSize: 12, fontWeight: FontWeight.w400, color: p.textMuted),
        labelLarge: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
            letterSpacing: 0.1),
        labelMedium: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: p.textSecondary,
            letterSpacing: 0.3),
        labelSmall: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: p.textMuted,
            letterSpacing: 0.3),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.ibmPlexSans(
            fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary),
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: p.textSecondary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: p.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: p.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
        labelStyle: GoogleFonts.ibmPlexSans(
            fontSize: 14, fontWeight: FontWeight.w400, color: p.textMuted),
        hintStyle: GoogleFonts.ibmPlexSans(fontSize: 14, color: p.textMuted),
        errorStyle: GoogleFonts.ibmPlexSans(fontSize: 12, color: p.error),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.primaryDim,
        labelStyle:
            GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide(color: p.border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme:
          DividerThemeData(color: p.borderLight, thickness: 1, space: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.transparent, elevation: 0),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor:
            brightness == Brightness.dark ? Colors.black : Colors.white,
        elevation: 4,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceElevated,
        contentTextStyle:
            GoogleFonts.ibmPlexSans(fontSize: 14, color: p.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceVariant,
        elevation: 24,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        titleTextStyle: GoogleFonts.ibmPlexSans(
            fontSize: 18, fontWeight: FontWeight.w600, color: p.textPrimary),
        contentTextStyle:
            GoogleFonts.ibmPlexSans(fontSize: 14, color: p.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceVariant,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0))),
        elevation: 16,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: GoogleFonts.ibmPlexSans(
            fontSize: 14, fontWeight: FontWeight.w500, color: p.textPrimary),
        subtitleTextStyle:
            GoogleFonts.ibmPlexSans(fontSize: 12, color: p.textMuted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.primary : p.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.primaryDim : p.surface),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.primary,
        labelStyle:
            GoogleFonts.ibmPlexSans(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            GoogleFonts.ibmPlexSans(fontSize: 13, fontWeight: FontWeight.w400),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.borderLight,
      ),
    );
  }
}
