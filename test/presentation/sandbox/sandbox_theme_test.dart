import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';

void main() {
  group('SandboxThemeExtension — cognitive shield tokens', () {
    test('default tokens use warning/amber and production surface blend', () {
      final ext = SandboxThemeExtension.defaults();

      expect(ext.accentColor, VeraProbColors.warning);
      expect(ext.tableBorderColor, VeraProbColors.warning);
      expect(
        ext.bannerBackgroundColor,
        VeraProbColors.warning.withValues(alpha: 0.15),
      );
      expect(
        ext.hatchOverlayColor,
        VeraProbColors.warning.withValues(alpha: 0.05),
      );
      expect(ext.simulatedValueColor, VeraProbColors.textSecondary);
      expect(ext.currencyPrefix, '~');
    });

    test('lerp blends accent toward other extension', () {
      final a = SandboxThemeExtension.defaults();
      final b = a.copyWith(accentColor: VeraProbColors.error);
      final mid = a.lerp(b, 0.5);
      expect(mid.accentColor, isNot(equals(a.accentColor)));
      expect(mid.tableBorderColor, VeraProbColors.warning);
    });

    test('ThemeData.copyWith registers extension for Theme.of lookup', () {
      final theme = ThemeData.dark().copyWith(
        extensions: [SandboxThemeExtension.defaults()],
      );
      final resolved = theme.extension<SandboxThemeExtension>();
      expect(resolved, isNotNull);
      expect(resolved!.accentColor, VeraProbColors.warning);
      expect(resolved.tableBorderColor, VeraProbColors.warning);
    });
  });

  group('SandboxCurrencyFormat — ~ prefix on financial values', () {
    test('formats int cents as ~R\$ with BR separators', () {
      expect(SandboxCurrencyFormat.formatCents(1245000), '~R\$ 12.450,00');
      expect(SandboxCurrencyFormat.formatCents(0), '~R\$ 0,00');
      expect(SandboxCurrencyFormat.formatCents(99), '~R\$ 0,99');
      expect(SandboxCurrencyFormat.formatCents(100), '~R\$ 1,00');
    });

    test('int extension applies sandbox prefix', () {
      expect(1245000.toSandboxBrl(), '~R\$ 12.450,00');
      expect((-1500).toSandboxBrl(), '~R\$ -15,00');
    });

    test('does not leak bare R\$ without tilde for simulated values', () {
      final formatted = SandboxCurrencyFormat.formatCents(8420000);
      expect(formatted.startsWith('~'), isTrue);
      expect(formatted, contains('R\$'));
      expect(formatted, isNot(startsWith('R\$')));
    });
  });
}
