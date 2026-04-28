import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

/// Banner displayed in the admin dashboard when the org has active quota warnings.
///
/// Nudges the admin to contact their account manager for an upgrade.
class UpgradeNudgeBanner extends ConsumerWidget {
  const UpgradeNudgeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warningsAsync = ref.watch(activeQuotaWarningsProvider);

    return warningsAsync.when(
      data: (warnings) {
        if (warnings.isEmpty) return const SizedBox.shrink();

        // Show the highest threshold warning
        final highest = warnings.first;
        final color = highest.isCritical
            ? VeraProbColors.error
            : highest.isUrgent
            ? Colors.orange
            : VeraProbColors.warning;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: color.withValues(alpha: 0.1),
          child: Row(
            children: [
              Icon(
                highest.isCritical
                    ? Icons.error_outline
                    : Icons.warning_amber_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  highest.isCritical
                      ? 'Atenção: Você atingiu ${highest.usagePct}% do limite de ${highest.resource}. '
                            'Entre em contato com seu gerente de conta para upgrade.'
                      : 'Aviso: Uso de ${highest.resource} em ${highest.usagePct}% '
                            '(${highest.currentCount}/${highest.maxAllowed}). '
                            'Considere solicitar um upgrade.',
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
