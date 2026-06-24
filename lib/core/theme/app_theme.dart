import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Operational color system for veraprob Control Center.
///
/// Designed for 24/7 operations: dark base reduces eye strain,
/// status colors follow industry standards for transport control rooms.
class VeraProbColors {
  VeraProbColors._();

  // ── Industrial Dark Theme (Tier-1 OCC, 24/7 Fatigue Reduction) ───
  static const Color background = Color(0xFF0A0A0F); // Near-black charcoal
  static const Color surface = Color(0xFF12121F); // Deep slate-violet
  static const Color surfaceElevated = Color(0xFF1E1E2F); // Elevated surface
  static const Color border = Color(0x0DFFFFFF); // Whisper border (white @5%)

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
  static const Color accent = Color(0xFF38BDF8); // Sky-400 — sidebar hover

  // ── Premium Text Hierarchy (Dark Mode Defaults) ──────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8); // Slate-400
  static const Color textDisabled = Color(0xFF475569);

  // ── Light Mode Palette (Zinc/Slate) ─────────────────────
  static const Color lightBackground = Color(0xFFF8FAFC); // Slate-50
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF1F5F9); // Slate-100
  static const Color lightBorder = Color(0xFFE2E8F0); // Slate-200
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate-950
  static const Color lightTextSecondary = Color(0xFF475569); // Slate-600
  static const Color lightTextDisabled = Color(0xFF94A3B8); // Slate-400

  // ── Semantic ─────────────────────────────────────────
  static const success = onTime;
  static const warning = delayed;
  static const error = critical;
  static const info = scheduled;

  /// Forensic verdict action — ONLY for CONFIRMAR/ANULAR verdict buttons.
  /// Violet: no positive/negative financial semantic in this codebase (INV-23).
  static const Color verdictAction = Color(0xFF7C3AED);
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
  static TextStyle get base {
    try {
      // Direct check to avoid any side effects in test zones
      if (!GoogleFonts.config.allowRuntimeFetching) {
        return const TextStyle(fontFamily: 'Lato');
      }
      return GoogleFonts.inter();
    } catch (_) {
      // Ultimate fallback to avoid crashing the theme initialization
      return const TextStyle(fontFamily: 'Lato');
    }
  }

  /// Display/heading face (Outfit) for KPI values and section titles.
  /// Falls back to [base] in test zones where runtime font fetch is disabled.
  static TextStyle get heading {
    try {
      if (!GoogleFonts.config.allowRuntimeFetching) {
        return base;
      }
      return GoogleFonts.outfit();
    } catch (_) {
      return base;
    }
  }

  static TextStyle get kpiValue => heading.copyWith(
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

  static TextStyle get sectionTitle => heading.copyWith(
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

  static final darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: VeraProbTypography.base.fontFamily,
      scaffoldBackgroundColor: VeraProbColors.background,
      focusColor: VeraProbColors.primary.withValues(alpha: 0.4),
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
        outline: VeraProbColors.border,
      ),
      textTheme: (() {
        final textTheme = TextTheme(
          headlineLarge: VeraProbTypography.kpiValue,
          headlineMedium: VeraProbTypography.kpiValue.copyWith(fontSize: 24),
          titleLarge: VeraProbTypography.sectionTitle.copyWith(fontSize: 18),
          titleMedium: VeraProbTypography.sectionTitle,
          titleSmall: VeraProbTypography.fieldLabel.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: VeraProbTypography.dataValue,
          bodyMedium: VeraProbTypography.bodyMedium,
          bodySmall: VeraProbTypography.bodySmall,
          labelLarge: VeraProbTypography.badge.copyWith(fontSize: 12),
          labelMedium: VeraProbTypography.badge,
          labelSmall: VeraProbTypography.caption,
        );

        try {
          // Pre-emptive check to avoid async errors in test zones
          if (!GoogleFonts.config.allowRuntimeFetching) {
            return textTheme;
          }
          return GoogleFonts.interTextTheme(textTheme);
        } catch (_) {
          return textTheme;
        }
      })(),
      appBarTheme: const AppBarTheme(
        backgroundColor: VeraProbColors.surface,
        foregroundColor: VeraProbColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
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
      iconTheme: const IconThemeData(
        color: VeraProbColors.textSecondary,
        size: 20,
      ),
      dividerTheme: const DividerThemeData(
        color: VeraProbColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: VeraProbColors.surface,
        disabledColor: VeraProbColors.surface,
        selectedColor: VeraProbColors.primary.withValues(alpha: 0.15),
        secondarySelectedColor: VeraProbColors.secondary.withValues(
          alpha: 0.15,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: VeraProbTypography.badge.copyWith(
          color: VeraProbColors.textPrimary,
        ),
        secondaryLabelStyle: VeraProbTypography.badge.copyWith(
          color: VeraProbColors.primary,
        ),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: VeraProbColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VeraProbColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: VeraProbTypography.sectionTitle.copyWith(fontSize: 18),
        contentTextStyle: VeraProbTypography.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VeraProbColors.surfaceElevated,
        contentTextStyle: VeraProbTypography.bodyMedium,
        actionTextColor: VeraProbColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VeraProbColors.primary;
          }
          return VeraProbColors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VeraProbColors.primary.withValues(alpha: 0.3);
          }
          return VeraProbColors.surfaceElevated;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VeraProbColors.primary;
          }
          return Colors.transparent;
        }),
        side: const BorderSide(color: VeraProbColors.textDisabled),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.all(VeraProbColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VeraProbColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
          borderSide: const BorderSide(
            color: VeraProbColors.primary,
            width: 1.5,
          ),
        ),
        labelStyle: VeraProbTypography.fieldLabel,
        hintStyle: VeraProbTypography.caption,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VeraProbColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: VeraProbTypography.badge.copyWith(
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: VeraProbColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: VeraProbColors.border),
          textStyle: VeraProbTypography.badge.copyWith(
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VeraProbColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: VeraProbTypography.badge.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: VeraProbColors.background,
        indicatorColor: VeraProbColors.primary.withValues(alpha: 0.15),
        selectedIconTheme: const IconThemeData(
          color: VeraProbColors.primary,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: VeraProbColors.textDisabled,
          size: 24,
        ),
        selectedLabelTextStyle: VeraProbTypography.sectionTitle.copyWith(
          fontSize: 13,
        ),
        unselectedLabelTextStyle: VeraProbTypography.caption.copyWith(
          fontSize: 13,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: VeraProbColors.surfaceElevated,
        headerBackgroundColor: VeraProbColors.surface,
        headerForegroundColor: VeraProbColors.textPrimary,
        surfaceTintColor: Colors.transparent,
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
          return null;
        }),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VeraProbColors.background;
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
  }

  static final lightTheme = _buildLightTheme();

  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: VeraProbTypography.base.fontFamily,
      scaffoldBackgroundColor: VeraProbColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: VeraProbColors.primary,
        secondary: VeraProbColors.secondary,
        surface: VeraProbColors.lightSurface,
        error: VeraProbColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: VeraProbColors.lightTextPrimary,
        onError: Colors.white,
        surfaceContainer: VeraProbColors.lightSurface,
        surfaceContainerHigh: VeraProbColors.lightSurfaceElevated,
      ),
      textTheme: (() {
        const textTheme = TextTheme(
          headlineMedium: TextStyle(
            color: VeraProbColors.lightTextPrimary,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: TextStyle(
            color: VeraProbColors.lightTextPrimary,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: VeraProbColors.lightTextPrimary),
          bodySmall: TextStyle(color: VeraProbColors.lightTextSecondary),
        );

        try {
          // Pre-emptive check to avoid async errors in test zones
          if (!GoogleFonts.config.allowRuntimeFetching) {
            return textTheme;
          }
          return GoogleFonts.interTextTheme(textTheme);
        } catch (_) {
          return textTheme;
        }
      })(),
      appBarTheme: const AppBarTheme(
        backgroundColor: VeraProbColors.lightSurface,
        foregroundColor: VeraProbColors.lightTextPrimary,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: VeraProbColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: VeraProbColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: VeraProbColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(
        color: VeraProbColors.lightTextSecondary,
        size: 20,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VeraProbColors.lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VeraProbColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VeraProbColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: VeraProbColors.primary,
            width: 1.5,
          ),
        ),
        labelStyle: const TextStyle(
          color: VeraProbColors.lightTextSecondary,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(
          color: VeraProbColors.lightTextDisabled,
          fontSize: 13,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VeraProbColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: VeraProbColors.lightBackground,
        indicatorColor: VeraProbColors.primary.withValues(alpha: 0.1),
        selectedIconTheme: const IconThemeData(
          color: VeraProbColors.primary,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: VeraProbColors.lightTextDisabled,
          size: 24,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: VeraProbColors.lightTextPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: VeraProbColors.lightTextDisabled,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: VeraProbColors.lightSurface,
        headerBackgroundColor: VeraProbColors.primary,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: VeraProbColors.lightBorder, width: 1),
        ),
        dayStyle: VeraProbTypography.bodyMedium.copyWith(
          color: VeraProbColors.lightTextPrimary,
        ),
        weekdayStyle: VeraProbTypography.caption.copyWith(
          color: VeraProbColors.lightTextSecondary,
        ),
        yearStyle: VeraProbTypography.bodyMedium.copyWith(
          color: VeraProbColors.lightTextPrimary,
        ),
        todayBorder: const BorderSide(color: VeraProbColors.primary),
        todayForegroundColor: WidgetStateProperty.all(VeraProbColors.primary),
        dayOverlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VeraProbColors.primary;
          }
          return null;
        }),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VeraProbColors.lightTextPrimary;
        }),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: VeraProbColors.lightTextSecondary,
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: VeraProbColors.primary,
        ),
      ),
    );
  }

  // ── Helpers for custom widgets ──────────────────────────
  static Color get primaryColor => VeraProbColors.primary;
  static Color get surfaceColor => VeraProbColors.background;
  static Gradient get primaryGradient => const LinearGradient(
    colors: [VeraProbColors.primary, VeraProbColors.secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
