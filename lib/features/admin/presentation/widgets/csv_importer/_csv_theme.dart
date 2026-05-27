import 'package:flutter/material.dart';

/// Shared Industrial Dark color tokens for CSV importer widgets.
/// Public so sub-files in the csv_importer/ directory can import it.
abstract final class CsvT {
  static const bgDeep = Color(0xFF0A0A0A);
  static const bgCard = Color(0xFF0F172A);
  static const bgSlate = Color(0xFF1A1A2E);
  static const border = Color.fromRGBO(255, 255, 255, 0.06);
  static const action = Color(0xFF00A3FF);
  static const success = Color(0xFF34C759);
  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFFFCC00);
  static const textHi = Color(0xFFE5E5E5);
  static const textLo = Color(0xFFA0A0A0);
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
