import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';

/// Persistent top banner for SLA Sandbox mode — cognitive shield against
/// mistaking hypothetical results for production ledger truth.
///
/// Non-dismissible: no close icon. Exit only via [onExit] ("Sair Simulação").
class SandboxBanner extends StatelessWidget {
  final String sessionLabel;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final VoidCallback onExit;

  const SandboxBanner({
    super.key,
    required this.sessionLabel,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<SandboxThemeExtension>() ??
        SandboxThemeExtension.defaults();

    final periodText =
        '${_formatUtc(periodStartUtc)} a ${_formatUtc(periodEndUtc)}';

    return Material(
      color: tokens.bannerBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.accentColor, width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: VeraProbSpacing.md,
            vertical: VeraProbSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: tokens.accentColor,
                size: 20,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: VeraProbTypography.bodySmall.copyWith(
                      color: VeraProbColors.textPrimary,
                    ),
                    children: [
                      TextSpan(
                        text: '⚠  MODO SIMULAÇÃO',
                        style: VeraProbTypography.sectionTitle.copyWith(
                          color: tokens.accentColor,
                          fontSize: 13,
                        ),
                      ),
                      TextSpan(
                        text:
                            '  ·  Regras hipotéticas aplicadas sobre dados '
                            'históricos de $periodText  ·  Sessão: "$sessionLabel"',
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              TextButton(
                onPressed: onExit,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: VeraProbSpacing.sm,
                    vertical: VeraProbSpacing.xs,
                  ),
                ),
                child: const Text('Sair Simulação'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// INV-6: display from UTC calendar fields (no local timezone shift).
  /// Locale-free so widget tests need no `initializeDateFormatting`.
  static String _formatUtc(DateTime utc) {
    final d = utc.isUtc ? utc : utc.toUtc();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
