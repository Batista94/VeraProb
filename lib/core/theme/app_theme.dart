import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Operational color system for BusFlow Control Center.
///
/// Designed for 24/7 operations: dark base reduces eye strain,
/// status colors follow industry standards for transport control rooms.
class BusFlowColors {
  BusFlowColors._();

  // ── Premium Dark Theme (Deep Navy/Obsidian) ────────────────
  static const Color background = Color(0xFF121212); // Softer than pure black
  static const Color surface = Color(0xFF1E1E24);    // Deep modern slate
  static const Color surfaceElevated = Color(0xFF2B2B36); // Noticeable elevation
  static const Color border = Color(0xFF333340);

  // ── Status Colors (CFO & Ops Friendly, Desaturated for Dark Mode) ─
  static const Color onTime = Color(0xFF10B981);    // Emerald Green
  static const Color delayed = Color(0xFFFBBF24);   // Desaturated Amber
  static const Color critical = Color(0xFFF87171);  // Desaturated Rose Red
  static const Color scheduled = Color(0xFF60A5FA); // Desaturated Royal Blue
  static const Color neutral = Color(0xFF64748B);

  // ── High-Impact Accents ─────────────────────────────────
  // A calmer, more premium teal.
  static const Color primary = Color(0xFF2DD4BF);   
  static const Color secondary = Color(0xFF818CF8); // Desaturated Indigo

  // ── Premium Text Hierarchy ──────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF475569);

  // ── Semantic ─────────────────────────────────────────
  static const success = onTime;
  static const warning = delayed;
  static const error = critical;
  static const info = scheduled;
}

/// Operational typography for dense information display.
class BusFlowTypography {
  BusFlowTypography._();

  // Use Inter as the premium bridge between UI and Data
  static TextStyle get base => GoogleFonts.inter();

  static TextStyle get kpiValue => base.copyWith(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: BusFlowColors.textPrimary,
    letterSpacing: -0.7,
  );

  static TextStyle get kpiLabel => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: BusFlowColors.textSecondary,
    letterSpacing: 0.8,
    textBaseline: TextBaseline.alphabetic,
  );

  static TextStyle get sectionTitle => base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: BusFlowColors.textPrimary,
    letterSpacing: 0.2,
  );

  static TextStyle get bodyMedium => base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: BusFlowColors.textPrimary,
  );

  static TextStyle get bodySmall => base.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: BusFlowColors.textSecondary,
  );

  static TextStyle get caption => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: BusFlowColors.textDisabled,
  );

  static TextStyle get badge => base.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
}

/// Main theme configuration for the BusFlow admin panel.
class AppTheme {
  AppTheme._();

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.inter().fontFamily,
    scaffoldBackgroundColor: BusFlowColors.background,
    colorScheme: const ColorScheme.dark(
      primary: BusFlowColors.primary,
      secondary: BusFlowColors.secondary,
      surface: BusFlowColors.surface,
      error: BusFlowColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: BusFlowColors.textPrimary,
      onError: Colors.white,
      surfaceContainer: BusFlowColors.surface,
      surfaceContainerHigh: BusFlowColors.surfaceElevated,
    ),
    textTheme: GoogleFonts.interTextTheme(const TextTheme(
      headlineMedium: TextStyle(color: BusFlowColors.textPrimary, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(color: BusFlowColors.textPrimary, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: BusFlowColors.textPrimary),
      bodySmall: TextStyle(color: BusFlowColors.textSecondary),
    )),
    appBarTheme: const AppBarTheme(
      backgroundColor: BusFlowColors.surface,
      foregroundColor: BusFlowColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 64, // Slightly taller for premium feel
    ),
    cardTheme: CardThemeData(
      color: BusFlowColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BusFlowColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: BusFlowColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(
      color: BusFlowColors.textSecondary,
      size: 20,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BusFlowColors.background, // Nested feel
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BusFlowColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BusFlowColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BusFlowColors.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: BusFlowColors.textSecondary, fontSize: 13),
      hintStyle: TextStyle(color: BusFlowColors.textDisabled, fontSize: 13),
      isDense: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BusFlowColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: BusFlowColors.background, // Match background so it blends natively
      indicatorColor: BusFlowColors.primary.withValues(alpha: 0.15),
      selectedIconTheme: const IconThemeData(color: BusFlowColors.primary, size: 24),
      unselectedIconTheme: const IconThemeData(color: BusFlowColors.textDisabled, size: 24),
      selectedLabelTextStyle: const TextStyle(
        color: BusFlowColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: BusFlowColors.textDisabled,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: BusFlowColors.surfaceElevated,
      headerBackgroundColor: BusFlowColors.surface,
      headerForegroundColor: BusFlowColors.textPrimary,
      surfaceTintColor: Colors.transparent, // Disable Material 3 subtle tint parsing
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: BusFlowColors.border, width: 1),
      ),
      dayStyle: BusFlowTypography.bodyMedium,
      weekdayStyle: BusFlowTypography.caption,
      yearStyle: BusFlowTypography.bodyMedium,
      todayBorder: const BorderSide(color: BusFlowColors.primary),
      todayForegroundColor: WidgetStateProperty.all(BusFlowColors.primary),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BusFlowColors.primary;
        }
        return null; // Defer to default
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BusFlowColors.background; // Dark text on bright primary
        }
        return BusFlowColors.textPrimary;
      }),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: BusFlowColors.textSecondary),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: BusFlowColors.primary),
    ),
  );

  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: BusFlowColors.primary,
    fontFamily: GoogleFonts.inter().fontFamily,
  );
}
