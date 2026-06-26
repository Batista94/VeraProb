import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';

/// Shared Industrial Dark color tokens for CSV importer widgets.
/// Public so sub-files in the csv_importer/ directory can import it.
abstract final class CsvT {
  static const bgDeep = VeraProbColors.background;
  static const bgCard = VeraProbColors.surface;
  static const bgSlate = VeraProbColors.surfaceElevated;
  static const border = VeraProbColors.border;
  static const action = VeraProbColors.primary;
  static const success = VeraProbColors.success;
  static const error = VeraProbColors.error;
  static const warning = VeraProbColors.warning;
  static const textHi = VeraProbColors.textPrimary;
  static const textLo = VeraProbColors.textSecondary;
  static const radiusCard = 12.0;
  static const radiusChip = 8.0;
  static const animDuration = Duration(milliseconds: 200);
  static const animCurve = Cubic(0.4, 0, 0.2, 1);

  static BoxDecoration cardDecoration({double radius = radiusCard}) =>
      BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      );

  static TextStyle labelStyle({Color color = textHi, double size = 13}) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      );
}
