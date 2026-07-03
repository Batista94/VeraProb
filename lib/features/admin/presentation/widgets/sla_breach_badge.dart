import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

/// Componente 4.4 — SLA breach counter in the [AuditorQueueScreen] header.
///
/// Renders a red, tappable pill counting disputes already past their
/// `resolution_due_at` deadline ([overdueDisputesCountProvider]). Tapping drills
/// the queue down to the breached cohort: it flips the filter to the `disputed`
/// lane and turns on [disputeOverdueOnlyProvider] so only overdue items show.
///
/// Healthy state renders **nothing** ([SizedBox.shrink]) — never a "0" badge —
/// so the header stays quiet until an actual breach demands attention.
class SlaBreachBadge extends ConsumerWidget {
  const SlaBreachBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueCount = ref.watch(overdueDisputesCountProvider);
    if (overdueCount == 0) return const SizedBox.shrink();

    const red = VeraProbColors.error;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'SLA de disputa vencido — abrir fila de vencidas',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('sla-breach-badge'),
            borderRadius: VeraProbRadii.mdAll,
            onTap: () {
              ref.read(disputeOverdueOnlyProvider.notifier).set(true);
              ref
                  .read(auditorQueueFilterProvider.notifier)
                  .setFilter(AuditorQueueFilter.disputed);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.12),
                borderRadius: VeraProbRadii.mdAll,
                border: Border.all(color: red.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.alarm_outlined, size: 14, color: red),
                  const SizedBox(width: 6),
                  Text(
                    'SLA VENCIDO · $overdueCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
