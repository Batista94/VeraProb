import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Operational color system for veraprob Control Center.
///
/// Designed for 24/7 operations: dark base reduces eye strain,
/// status colors follow industry standards for transport control rooms.
class VeraProbColors {
  VeraProbColors._();

  // ── Industrial Slate/Zinc Theme (24/7 Fatigue Reduction) ───
  static const Color background = Color(0xFF0F172A); // Slate-950
  static const Color surface = Color(0xFF1E293B); // Slate-800
  static const Color surfaceElevated = Color(0xFF334155); // Slate-700
  static const Color border = Color(0xFF334155); // Slate-700 @40%

  // ── Status Colors (CFO & Ops Friendly, Desaturated for Dark Mode) ─
  static const Color onTime = Color(0xFF10B981); // Emerald Green
  static const Color delayed = Color(0xFFFBBF24); // Desaturated Amber
  static const Color critical = Color(0xFFF87171); // Desaturated Rose Red
  static const Color scheduled = Color(0xFF60A5FA); // Desaturated Royal Blue
  static const Color neutral = Color(0xFF64748B);

  // ── SuperAdmin Surface (INV-6 visual indicator) ─────────
  static const Color superAdminSurface = Color(0xFF1E1B4B);

  // ── High-Impact Accents ─────────────────────────────────
  // A calmer, more premium teal.
  static const Color primary = Color(0xFF2DD4BF);
  static const Color secondary = Color(0xFF818CF8); // Desaturated Indigo

  // ── Premium Text Hierarchy ──────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8); // Slate-400 ~4.5:1 on #0F172A (WCAG AA)
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
class VeraProbSpacing {
  VeraProbSpacing._();

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
class VeraProbTypography {
  VeraProbTypography._();

  // Use Inter as the premium bridge between UI and Data
  static TextStyle get base => GoogleFonts.inter();

  static TextStyle get kpiValue => base.copyWith(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: VeraProbColors.textPrimary,
    letterSpacing: -0.7,
  );

  static TextStyle get kpiLabel => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: VeraProbColors.textSecondary,
    letterSpacing: 0.8,
    textBaseline: TextBaseline.alphabetic,
  );

  static TextStyle get sectionTitle => base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: VeraProbColors.textPrimary,
    letterSpacing: 0.2,
  );

  static TextStyle get bodyMedium => base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: VeraProbColors.textPrimary,
  );

  static TextStyle get bodySmall => base.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: VeraProbColors.textSecondary,
  );

  static TextStyle get caption => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: VeraProbColors.textDisabled,
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
    color: VeraProbColors.textPrimary,
  );

  /// For form field labels and section sub-headers inside forms.
  static TextStyle get fieldLabel => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: VeraProbColors.textSecondary,
    letterSpacing: 0.4,
  );
}

/// Main theme configuration for the veraprob admin panel.
class AppTheme {
  AppTheme._();

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.inter().fontFamily,
    scaffoldBackgroundColor: VeraProbColors.background,
    colorScheme: const ColorScheme.dark(
      primary: VeraProbColors.primary,
      secondary: VeraProbColors.secondary,
      surface: VeraProbColors.surface,
      error: VeraProbColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: VeraProbColors.textPrimary,
      onError: Colors.white,
      surfaceContainer: VeraProbColors.surface,
      surfaceContainerHigh: VeraProbColors.surfaceElevated,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        headlineMedium: TextStyle(
          color: VeraProbColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: VeraProbColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: VeraProbColors.textPrimary),
        bodySmall: TextStyle(color: VeraProbColors.textSecondary),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VeraProbColors.surface,
      foregroundColor: VeraProbColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 64, // Slightly taller for premium feel
    ),
    cardTheme: CardThemeData(
      color: VeraProbColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: VeraProbColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: VeraProbColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(
      color: VeraProbColors.textSecondary,
      size: 20,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VeraProbColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VeraProbColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VeraProbColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VeraProbColors.primary, width: 1.5),
      ),
      labelStyle: const TextStyle(
        color: VeraProbColors.textSecondary,
        fontSize: 13,
      ),
      hintStyle: const TextStyle(
        color: VeraProbColors.textDisabled,
        fontSize: 13,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VeraProbColors.primary,
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
          VeraProbColors.background, // Match background so it blends natively
      indicatorColor: VeraProbColors.primary.withValues(alpha: 0.15),
      selectedIconTheme: const IconThemeData(
        color: VeraProbColors.primary,
        size: 24,
      ),
      unselectedIconTheme: const IconThemeData(
        color: VeraProbColors.textDisabled,
        size: 24,
      ),
      selectedLabelTextStyle: const TextStyle(
        color: VeraProbColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: VeraProbColors.textDisabled,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: VeraProbColors.surfaceElevated,
      headerBackgroundColor: VeraProbColors.surface,
      headerForegroundColor: VeraProbColors.textPrimary,
      surfaceTintColor:
          Colors.transparent, // Disable Material 3 subtle tint parsing
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: VeraProbColors.border, width: 1),
      ),
      dayStyle: VeraProbTypography.bodyMedium,
      weekdayStyle: VeraProbTypography.caption,
      yearStyle: VeraProbTypography.bodyMedium,
      todayBorder: const BorderSide(color: VeraProbColors.primary),
      todayForegroundColor: WidgetStateProperty.all(VeraProbColors.primary),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return VeraProbColors.primary;
        }
        return null; // Defer to default
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return VeraProbColors.background; // Dark text on bright primary
        }
        return VeraProbColors.textPrimary;
      }),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: VeraProbColors.textSecondary,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: VeraProbColors.primary,
      ),
    ),
  );

  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: VeraProbColors.primary,
    fontFamily: GoogleFonts.inter().fontFamily,
  );

  // ── Helpers for custom widgets ──────────────────────────
  static Color get primaryColor => VeraProbColors.primary;
  static Color get surfaceColor => VeraProbColors.background;
  static Gradient get primaryGradient => const LinearGradient(
    colors: [VeraProbColors.primary, VeraProbColors.secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
