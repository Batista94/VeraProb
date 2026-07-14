import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Theme tokens for SLA Sandbox "cognitive shield" mode.
///
/// Visually distinguishes hypothetical simulation data from production ledger
/// truth — amber accent, hatch overlay hint, and `~` currency prefix.
@immutable
class SandboxThemeExtension extends ThemeExtension<SandboxThemeExtension> {
  /// Amber accent used for banner stripe, badges, and cognitive cues.
  final Color accentColor;

  /// Left border / row accent for result tables (warning).
  final Color tableBorderColor;

  /// Banner fill: warning @ 15% over [VeraProbColors.surface].
  final Color bannerBackgroundColor;

  /// Subtle diagonal-hatch overlay tint (warning @ 5%).
  final Color hatchOverlayColor;

  /// Typography color for simulated financial values ([VeraProbColors.textSecondary]).
  final Color simulatedValueColor;

  /// Prefix applied to simulated currency strings (plan: `~`).
  final String currencyPrefix;

  const SandboxThemeExtension({
    required this.accentColor,
    required this.tableBorderColor,
    required this.bannerBackgroundColor,
    required this.hatchOverlayColor,
    required this.simulatedValueColor,
    this.currencyPrefix = '~',
  });

  factory SandboxThemeExtension.defaults() {
    return SandboxThemeExtension(
      accentColor: VeraProbColors.warning,
      tableBorderColor: VeraProbColors.warning,
      bannerBackgroundColor: VeraProbColors.warning.withValues(alpha: 0.15),
      hatchOverlayColor: VeraProbColors.warning.withValues(alpha: 0.05),
      simulatedValueColor: VeraProbColors.textSecondary,
      currencyPrefix: '~',
    );
  }

  /// Typography for simulated monetary labels — secondary, never production primary.
  TextStyle get simulatedValueStyle =>
      VeraProbTypography.dataValue.copyWith(color: simulatedValueColor);

  @override
  SandboxThemeExtension copyWith({
    Color? accentColor,
    Color? tableBorderColor,
    Color? bannerBackgroundColor,
    Color? hatchOverlayColor,
    Color? simulatedValueColor,
    String? currencyPrefix,
  }) {
    return SandboxThemeExtension(
      accentColor: accentColor ?? this.accentColor,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      bannerBackgroundColor:
          bannerBackgroundColor ?? this.bannerBackgroundColor,
      hatchOverlayColor: hatchOverlayColor ?? this.hatchOverlayColor,
      simulatedValueColor: simulatedValueColor ?? this.simulatedValueColor,
      currencyPrefix: currencyPrefix ?? this.currencyPrefix,
    );
  }

  @override
  SandboxThemeExtension lerp(
    ThemeExtension<SandboxThemeExtension>? other,
    double t,
  ) {
    if (other is! SandboxThemeExtension) return this;
    return SandboxThemeExtension(
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      tableBorderColor: Color.lerp(
        tableBorderColor,
        other.tableBorderColor,
        t,
      )!,
      bannerBackgroundColor: Color.lerp(
        bannerBackgroundColor,
        other.bannerBackgroundColor,
        t,
      )!,
      hatchOverlayColor: Color.lerp(
        hatchOverlayColor,
        other.hatchOverlayColor,
        t,
      )!,
      simulatedValueColor: Color.lerp(
        simulatedValueColor,
        other.simulatedValueColor,
        t,
      )!,
      currencyPrefix: t < 0.5 ? currencyPrefix : other.currencyPrefix,
    );
  }
}

/// Formats BIGINT cents as sandbox BRL with the cognitive `~` prefix.
///
/// Example: `1245000` → `~R$ 12.450,00`
abstract final class SandboxCurrencyFormat {
  static String formatCents(int cents, {String prefix = '~'}) {
    final negative = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final decimal = (abs % 100).toString().padLeft(2, '0');
    final amount = _formatThousands(whole);
    final signed = negative ? '-$amount' : amount;
    return '$prefix'
        'R\$ $signed,$decimal';
  }

  static String _formatThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Convenience: `1245000.toSandboxBrl()` → `~R$ 12.450,00`.
extension SandboxCentsFormatting on int {
  String toSandboxBrl({String prefix = '~'}) =>
      SandboxCurrencyFormat.formatCents(this, prefix: prefix);
}
