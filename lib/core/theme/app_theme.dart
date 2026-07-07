import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Operational color system for VeraProb Control Center.
///
/// Palette: Indigo Zinc — Linear/Vercel-like aesthetic.
/// Designed for 24/7 operations: dark base reduces eye strain.
/// Semantic financial coloring: Emerald (Savings), Red (Penalties), Amber (Risk).
class VeraProbColors {
  VeraProbColors._();

  // ── Indigo Zinc Base ────────────────────────────────────────────────
  static const Color background = Color(0xFF09090B);
  static const Color surface = Color(0xFF1C1C21);
  static const Color surfaceElevated = Color(0xFF242429);
  static const Color border = Color(0x1AFFFFFF); // white @ 10%

  // ── Status Colors (desaturated for dark mode) ───────────────────────
  static const Color onTime = Color(0xFF10B981); // Emerald Green
  static const Color delayed = Color(0xFFF59E0B); // Amber
  static const Color critical = Color(0xFFEF4444); // Red
  static const Color scheduled = Color(0xFF60A5FA); // Blue
  static const Color neutral = Color(0xFF64748B);

  // ── SuperAdmin Surface (INV-6 visual indicator) ─────────────────────
  static const Color superAdminSurface = Color(0xFF1E1B4B);

  // ── Primary Palette ─────────────────────────────────────────────────
  static const Color primary = Color(0xFF6E7CF6); // Indigo
  static const Color accent = Color(0xFF93A0FF); // Indigo light
  static const Color secondary = Color(0xFF5EEAD4); // Teal (apoio)

  // ── Text Hierarchy ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFD4D4D8);
  static const Color textSecondary = Color(0xFF9B9BA6);
  static const Color textDisabled = Color(0xFF4E4E58);

  // ── Semantic ────────────────────────────────────────────────────────
  static const success = onTime;
  static const warning = delayed;
  static const error = critical;
  static const info = scheduled;

  /// Forensic verdict action — ONLY for CONFIRMAR/ANULAR verdict buttons.
  /// Violet: no positive/negative financial semantic (INV-23).
  static const Color verdictAction = Color(0xFF8B5CF6);
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

/// Border radius tokens — use instead of raw `BorderRadius.circular()`.
class VeraProbRadii {
  VeraProbRadii._();

  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
  static const double pill = 999.0;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion tokens — duration and easing constants.
class VeraProbMotion {
  VeraProbMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve curve = Curves.easeOutCubic;
}

/// Responsive breakpoints aligned with dominant literal usage in the codebase.
///
/// Use [isCompact] / [isMedium] helpers instead of raw width comparisons.
class VeraProbBreakpoints {
  VeraProbBreakpoints._();

  static const double compact = 600.0;
  static const double medium = 900.0;
  static const double wide = 1100.0;
  static const double maxContent = 1600.0;

  /// True when the viewport is narrower than [compact] (mobile/tablet portrait).
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  /// True when the viewport is between [compact] and [wide].
  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= compact && w < wide;
  }
}

/// Elevation tokens as shadow lists — use instead of raw `elevation` ints
/// where Box shadow control is required (e.g. custom containers).
class VeraProbElevation {
  VeraProbElevation._();

  /// No shadow — flat surface (level 0).
  static const List<BoxShadow> flat = [];

  /// Subtle lift — cards, panels (level 1).
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Strong lift — modals, popovers (level 2).
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
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
    fontWeight: FontWeight.w500,
    color: VeraProbColors.textSecondary,
  );

  static TextStyle get caption => base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: VeraProbColors.textSecondary,
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

  /// Monospaced style for hashes, IDs, and forensic data.
  static TextStyle mono({
    double size = 12,
    Color color = VeraProbColors.textPrimary,
    FontWeight? weight,
    double? letterSpacing,
  }) => base.copyWith(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
}

/// Main theme configuration for the VeraProb admin panel.
/// Dark-only product — light theme removed (Industrial Dark design system).
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
        // Dark foreground on accent fills — white fails 4.5:1 on this palette
        // (white/#6E7CF6 = 3.6:1; white/#5EEAD4 = 1.5:1).
        onPrimary: VeraProbColors.background,
        onSecondary: VeraProbColors.background,
        onSurface: VeraProbColors.textPrimary,
        onError: VeraProbColors.background,
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
      cardTheme: const CardThemeData(
        color: VeraProbColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: VeraProbRadii.lgAll,
          side: BorderSide(color: VeraProbColors.border, width: 1),
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
        shape: const RoundedRectangleBorder(
          borderRadius: VeraProbRadii.mdAll,
          side: BorderSide(color: VeraProbColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VeraProbColors.surface,
        elevation: 8,
        shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.xlAll),
        titleTextStyle: VeraProbTypography.sectionTitle.copyWith(fontSize: 18),
        contentTextStyle: VeraProbTypography.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VeraProbColors.surfaceElevated,
        contentTextStyle: VeraProbTypography.bodyMedium,
        actionTextColor: VeraProbColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.mdAll),
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
        shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.smAll),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.all(VeraProbColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VeraProbColors.surface,
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelStyle: VeraProbTypography.fieldLabel.copyWith(
          backgroundColor: VeraProbColors.surface,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: const OutlineInputBorder(
          borderRadius: VeraProbRadii.mdAll,
          borderSide: BorderSide(color: VeraProbColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: VeraProbRadii.mdAll,
          borderSide: BorderSide(color: VeraProbColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: VeraProbRadii.mdAll,
          borderSide: BorderSide(color: VeraProbColors.primary, width: 1.5),
        ),
        labelStyle: VeraProbTypography.fieldLabel,
        hintStyle: VeraProbTypography.caption,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VeraProbColors.primary,
          foregroundColor: VeraProbColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: VeraProbRadii.mdAll,
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
          shape: const RoundedRectangleBorder(
            borderRadius: VeraProbRadii.mdAll,
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
          color: VeraProbColors.textDisabled,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: VeraProbColors.surfaceElevated,
        headerBackgroundColor: VeraProbColors.surface,
        headerForegroundColor: VeraProbColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: VeraProbRadii.xlAll,
          side: BorderSide(color: VeraProbColors.border, width: 1),
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

  // ── Helpers for custom widgets ──────────────────────────
  static Color get primaryColor => VeraProbColors.primary;
  static Color get surfaceColor => VeraProbColors.background;
  static Gradient get primaryGradient => const LinearGradient(
    colors: [VeraProbColors.primary, VeraProbColors.accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
