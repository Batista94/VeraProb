import 'package:flutter/material.dart';

/// Operational color system for BusFlow Control Center.
///
/// Designed for 24/7 operations: dark base reduces eye strain,
/// status colors follow industry standards for transport control rooms.
class BusFlowColors {
  BusFlowColors._();

  // ── Dark Theme Base ──────────────────────────────────
  static const background = Color(0xFF0F1419);
  static const surface = Color(0xFF1A2332);
  static const surfaceElevated = Color(0xFF243044);
  static const border = Color(0xFF2D3F56);

  // ── Status Colors ────────────────────────────────────
  static const onTime = Color(0xFF00C853);
  static const delayed = Color(0xFFFF9100);
  static const critical = Color(0xFFFF1744);
  static const scheduled = Color(0xFF448AFF);
  static const neutral = Color(0xFF78909C);

  // ── Accent ───────────────────────────────────────────
  static const primary = Color(0xFF00BFA5);
  static const secondary = Color(0xFF7C4DFF);

  // ── Text ─────────────────────────────────────────────
  static const textPrimary = Color(0xFFECEFF1);
  static const textSecondary = Color(0xFF90A4AE);
  static const textDisabled = Color(0xFF546E7A);

  // ── Semantic ─────────────────────────────────────────
  static const success = onTime;
  static const warning = delayed;
  static const error = critical;
  static const info = scheduled;
}

/// Operational typography for dense information display.
class BusFlowTypography {
  BusFlowTypography._();

  static const String fontFamily = 'Roboto';

  static const kpiValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: BusFlowColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const kpiLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: BusFlowColors.textSecondary,
    letterSpacing: 0.5,
  );

  static const sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: BusFlowColors.textPrimary,
    letterSpacing: 0.3,
  );

  static const bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: BusFlowColors.textPrimary,
  );

  static const bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: BusFlowColors.textSecondary,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: BusFlowColors.textDisabled,
  );

  static const badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );
}

/// Main theme configuration for the BusFlow admin panel.
class AppTheme {
  AppTheme._();

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: BusFlowTypography.fontFamily,
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
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BusFlowColors.surface,
      foregroundColor: BusFlowColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 48,
    ),
    cardTheme: CardThemeData(
      color: BusFlowColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: BusFlowColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BusFlowColors.border),
      ),
      textStyle: BusFlowTypography.bodySmall.copyWith(
        color: BusFlowColors.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: const Duration(milliseconds: 300),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BusFlowColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: BusFlowColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: BusFlowColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: BusFlowColors.primary, width: 1.5),
      ),
      hintStyle: BusFlowTypography.bodySmall,
      isDense: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BusFlowColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BusFlowColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BusFlowColors.surfaceElevated,
      contentTextStyle: BusFlowTypography.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: BusFlowColors.border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        BusFlowColors.border.withValues(alpha: 0.6),
      ),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(4),
    ),
  );

  // Keep light theme for compatibility but admin will use dark
  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: BusFlowColors.primary,
    fontFamily: BusFlowTypography.fontFamily,
  );
}
