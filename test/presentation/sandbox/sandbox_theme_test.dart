import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';

void main() {
  group('SandboxTokens — cognitive shield tokens', () {
    test('tokens use warning/amber and production surface blend', () {
      expect(SandboxTokens.accentColor, VeraProbColors.warning);
      expect(SandboxTokens.tableBorderColor, VeraProbColors.warning);
      expect(
        SandboxTokens.bannerBackgroundColor,
        VeraProbColors.warning.withValues(alpha: 0.15),
      );
      expect(
        SandboxTokens.hatchOverlayColor,
        VeraProbColors.warning.withValues(alpha: 0.05),
      );
      expect(SandboxTokens.simulatedValueColor, VeraProbColors.textSecondary);
      expect(SandboxTokens.currencyPrefix, '~');
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

    test('formatThousands shares BR separator with currency', () {
      expect(SandboxCurrencyFormat.formatThousands(1500), '1.500');
      expect(SandboxCurrencyFormat.formatThousands(-2000), '-2.000');
    });
  });
}
