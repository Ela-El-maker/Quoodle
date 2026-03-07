import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );

    final colorScheme = const ColorScheme.light().copyWith(
      primary: AppColors.accentBlue,
      secondary: AppColors.accentMint,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceRaised,
      error: AppColors.nonCompliant,
      onPrimary: Colors.white,
      onSecondary: AppColors.textPrimary,
      onSurface: AppColors.textPrimary,
      onError: Colors.white,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.glassBorder,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.headlineSmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceRaised,
        selectedColor: AppColors.accentBlue.withValues(alpha: 0.12),
        disabledColor: AppColors.surfaceRaised,
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: const BorderSide(color: AppColors.glassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface.withValues(alpha: 0.96),
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        unselectedLabelStyle: textTheme.bodySmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        indicator: BoxDecoration(
          color: AppColors.accentBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.glassBorder),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          textStyle: textTheme.labelLarge,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentBlue,
        linearTrackColor: AppColors.surfaceRaised,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accentBlue;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accentBlue.withValues(alpha: 0.35);
          }
          return AppColors.surfaceRaised;
        }),
      ),
    );
  }
}
