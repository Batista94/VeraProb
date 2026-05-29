import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/core/theme/contrast_checker.dart';

/// WCAG 2.1 AA accessibility gate for the Industrial Dark palette.
///
/// Living CI gate: any palette change that drops a foreground/background
/// pair below its AA threshold fails the build. Thresholds follow
/// WCAG 2.1 SC 1.4.3 (4.5:1 normal text) and SC 1.4.11 (3:1 UI components).
void main() {
  group('WCAG 2.1 AA contrast gate — Industrial Dark palette', () {
    const normalText = 4.5;
    const uiComponent = 3.0;

    void expectAtLeast(String label, Color fg, Color bg, double threshold) {
      final ratio = ContrastChecker.contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(threshold),
        reason: '$label = ${ratio.toStringAsFixed(2)}:1 (min $threshold:1)',
      );
    }

    test('primary text on dark surfaces meets normal-text AA', () {
      expectAtLeast(
        'textPrimary/background',
        VeraProbColors.textPrimary,
        VeraProbColors.background,
        normalText,
      );
      expectAtLeast(
        'textPrimary/surface',
        VeraProbColors.textPrimary,
        VeraProbColors.surface,
        normalText,
      );
    });

    test('secondary text on dark surfaces meets normal-text AA', () {
      expectAtLeast(
        'textSecondary/background',
        VeraProbColors.textSecondary,
        VeraProbColors.background,
        normalText,
      );
      expectAtLeast(
        'textSecondary/surface',
        VeraProbColors.textSecondary,
        VeraProbColors.surface,
        normalText,
      );
    });

    test('primary accent as UI component on background meets AA', () {
      expectAtLeast(
        'primary/background',
        VeraProbColors.primary,
        VeraProbColors.background,
        uiComponent,
      );
    });

    // textDisabled is intentionally NOT tested.
    // WCAG 2.1 SC 1.4.3: disabled UI components are exempt.

    test('evidence chip foregrounds meet UI-component AA over 0.12 tint', () {
      const chipForegrounds = <String, Color>{
        'critical': VeraProbColors.critical,
        'delayed': VeraProbColors.delayed,
        'onTime': VeraProbColors.onTime,
        'scheduled/info': VeraProbColors.info,
        'neutral-fallback': VeraProbColors.textSecondary,
      };
      chipForegrounds.forEach((label, color) {
        final ratio = ContrastChecker.alphaBlendedRatio(
          color,
          0.12,
          VeraProbColors.surface,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(uiComponent),
          reason: 'chip $label = ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });

    test('raw neutral fails AA as chip text (regression guard)', () {
      // #64748B ≈ 2.72:1 over its own 0.12 composite — below 3:1.
      // EvidenceCategoryChip MUST use textSecondary for the neutral fallback;
      // this guard prevents anyone re-introducing neutral as chip text.
      final ratio = ContrastChecker.alphaBlendedRatio(
        VeraProbColors.neutral,
        0.12,
        VeraProbColors.surface,
      );
      expect(ratio, lessThan(uiComponent));
    });
  });
}
