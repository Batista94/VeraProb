import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative-luminance contrast utilities.
///
/// Pure math — no extra dependencies. Backs the accessibility CI gate that
/// keeps the Industrial Dark palette legible for 24/7 OCC operation.
class ContrastChecker {
  ContrastChecker._();

  /// WCAG 2.1 contrast ratio between [fg] and [bg] (range 1.0 .. 21.0).
  static double contrastRatio(Color fg, Color bg) {
    final l1 = _relativeLuminance(fg);
    final l2 = _relativeLuminance(bg);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Composites [overlay] at [alpha] over opaque [bg], then returns the
  /// contrast ratio of [overlay] (as foreground text) over that blend.
  ///
  /// Mirrors how a tinted chip renders its label on top of its own
  /// translucent fill above [bg].
  static double alphaBlendedRatio(Color overlay, double alpha, Color bg) {
    final blended = Color.from(
      alpha: 1,
      red: overlay.r * alpha + bg.r * (1 - alpha),
      green: overlay.g * alpha + bg.g * (1 - alpha),
      blue: overlay.b * alpha + bg.b * (1 - alpha),
    );
    return contrastRatio(overlay, blended);
  }

  static double _relativeLuminance(Color c) =>
      0.2126 * _linearize(c.r) +
      0.7152 * _linearize(c.g) +
      0.0722 * _linearize(c.b);

  static double _linearize(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}
