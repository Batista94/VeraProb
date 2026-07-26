import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';

/// Cognitive-shield tokens for SLA Sandbox mode (amber vs production ledger).
///
/// Not a [ThemeExtension] — tokens are fixed design constants; screens read
/// [SandboxTokens] directly (ponytail: no lerp/copyWith until a second theme).
abstract final class SandboxTokens {
  static const Color accentColor = VeraProbColors.warning;
  static const Color tableBorderColor = VeraProbColors.warning;
  static final Color bannerBackgroundColor = VeraProbColors.warning.withValues(
    alpha: 0.15,
  );
  static final Color hatchOverlayColor = VeraProbColors.warning.withValues(
    alpha: 0.05,
  );
  static const Color simulatedValueColor = VeraProbColors.textSecondary;
  static const String currencyPrefix = '~';

  static TextStyle get simulatedValueStyle =>
      VeraProbTypography.dataValue.copyWith(color: simulatedValueColor);
}

/// Formats BIGINT cents as sandbox BRL with the cognitive `~` prefix.
///
/// Example: `1245000` → `~R$ 12.450,00`
abstract final class SandboxCurrencyFormat {
  static String formatCents(int cents, {String prefix = '~'}) {
    final body = BrlCurrencyInputFormatter.fromCents(cents.abs());
    if (cents < 0) {
      return '$prefix${body.replaceFirst('R\$ ', 'R\$ -')}';
    }
    return '$prefix$body';
  }

  /// BR thousands separator for integer magnitudes (e.g. bps).
  static String formatThousands(int n) {
    final negative = n < 0;
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }
}

/// Convenience: `1245000.toSandboxBrl()` → `~R$ 12.450,00`.
extension SandboxCentsFormatting on int {
  String toSandboxBrl({String prefix = '~'}) =>
      SandboxCurrencyFormat.formatCents(this, prefix: prefix);
}
