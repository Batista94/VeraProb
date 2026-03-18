import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Operational color system for PactaFlow Control Center.
///
/// Designed for 24/7 operations: dark base reduces eye strain,
/// status colors follow industry standards for transport control rooms.
class PactaFlowColors {
  PactaFlowColors._();

  // ── Premium Dark Theme (Deep Navy/Obsidian) ────────────────
  static const Color background = Color(0xFF121212); // Softer than pure black
  static const Color surface = Color(0xFF1E1E24); // Deep modern slate
  static const Color surfaceElevated = Color(
    0xFF2B2B36,
  ); // Noticeable elevation
  static const Color border = Color(0xFF333340);

  // ── Status Colors (CFO & Ops Friendly, Desaturated for Dark Mode) ─
  static const Color onTime = Color(0xFF10B981); // Emerald Green
  static const Color delayed = Color(0xFFFBBF24); // Desaturated Amber
  static const Color critical = Color(0xFFF87171); // Desaturated Rose Red
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

/// Spacing constants based on an 8px grid.
///
/// All paddings and gaps in the OCC must use these constants —
/// never raw pixel values — to maintain mathematical alignment.
class PactaFlowSpacing {
  PactaFlowSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  /// Standard padding for form sections and dialog bodies.
  static const EdgeInsets sectionPadding = EdgeInsets.all(md);

  /// Compact padding for cards and list items.
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );
}

/// Operational typography for dense information display.
class PactaFlowTypography {
  PactaFlowTypography._();

  // Use Inter as the premium bridge between UI and Data
  static TextStyle get base => GoogleFonts.inter();

  static TextStyle get kpiValue => base.copyWith(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: PactaFlowColors.textPrimary,
    letterSpacing: -0.7,
  );

  static TextStyle get kpiLabel => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: PactaFlowColors.textSecondary,
    letterSpacing: 0.8,
    textBaseline: TextBaseline.alphabetic,
  );

  static TextStyle get sectionTitle => base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: PactaFlowColors.textPrimary,
    letterSpacing: 0.2,
  );

  static TextStyle get bodyMedium => base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: PactaFlowColors.textPrimary,
  );

  static TextStyle get bodySmall => base.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: PactaFlowColors.textSecondary,
  );

  static TextStyle get caption => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: PactaFlowColors.textDisabled,
  );

  static TextStyle get badge => base.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  /// For contractual data values: contract name, monetary amounts, dates.
  /// Heavier than body to signal "this is a fact, not a label".
  static TextStyle get dataValue => base.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: PactaFlowColors.textPrimary,
  );

  /// For form field labels and section sub-headers inside forms.
  static TextStyle get fieldLabel => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: PactaFlowColors.textSecondary,
    letterSpacing: 0.4,
  );
}

/// Main theme configuration for the PactaFlow admin panel.
class AppTheme {
  AppTheme._();

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.inter().fontFamily,
    scaffoldBackgroundColor: PactaFlowColors.background,
    colorScheme: const ColorScheme.dark(
      primary: PactaFlowColors.primary,
      secondary: PactaFlowColors.secondary,
      surface: PactaFlowColors.surface,
      error: PactaFlowColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: PactaFlowColors.textPrimary,
      onError: Colors.white,
      surfaceContainer: PactaFlowColors.surface,
      surfaceContainerHigh: PactaFlowColors.surfaceElevated,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        headlineMedium: TextStyle(
          color: PactaFlowColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: PactaFlowColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: PactaFlowColors.textPrimary),
        bodySmall: TextStyle(color: PactaFlowColors.textSecondary),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PactaFlowColors.surface,
      foregroundColor: PactaFlowColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 64, // Slightly taller for premium feel
    ),
    cardTheme: CardThemeData(
      color: PactaFlowColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PactaFlowColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: PactaFlowColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(
      color: PactaFlowColors.textSecondary,
      size: 20,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PactaFlowColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: PactaFlowColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: PactaFlowColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: PactaFlowColors.primary,
          width: 1.5,
        ),
      ),
      labelStyle: const TextStyle(color: PactaFlowColors.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: PactaFlowColors.textDisabled, fontSize: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PactaFlowColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor:
          PactaFlowColors.background, // Match background so it blends natively
      indicatorColor: PactaFlowColors.primary.withValues(alpha: 0.15),
      selectedIconTheme: const IconThemeData(
        color: PactaFlowColors.primary,
        size: 24,
      ),
      unselectedIconTheme: const IconThemeData(
        color: PactaFlowColors.textDisabled,
        size: 24,
      ),
      selectedLabelTextStyle: const TextStyle(
        color: PactaFlowColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: PactaFlowColors.textDisabled,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: PactaFlowColors.surfaceElevated,
      headerBackgroundColor: PactaFlowColors.surface,
      headerForegroundColor: PactaFlowColors.textPrimary,
      surfaceTintColor:
          Colors.transparent, // Disable Material 3 subtle tint parsing
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PactaFlowColors.border, width: 1),
      ),
      dayStyle: PactaFlowTypography.bodyMedium,
      weekdayStyle: PactaFlowTypography.caption,
      yearStyle: PactaFlowTypography.bodyMedium,
      todayBorder: const BorderSide(color: PactaFlowColors.primary),
      todayForegroundColor: WidgetStateProperty.all(PactaFlowColors.primary),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return PactaFlowColors.primary;
        }
        return null; // Defer to default
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return PactaFlowColors.background; // Dark text on bright primary
        }
        return PactaFlowColors.textPrimary;
      }),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: PactaFlowColors.textSecondary,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: PactaFlowColors.primary,
      ),
    ),
  );

  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: PactaFlowColors.primary,
    fontFamily: GoogleFonts.inter().fontFamily,
  );

  // ── Helpers for custom widgets ──────────────────────────
  static Color get primaryColor => PactaFlowColors.primary;
  static Color get surfaceColor => PactaFlowColors.background;
  static Gradient get primaryGradient => const LinearGradient(
    colors: [PactaFlowColors.primary, PactaFlowColors.secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
