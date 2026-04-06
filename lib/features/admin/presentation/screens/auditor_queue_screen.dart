import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';

/// Tribunal de Auditoria — Human-in-the-Loop review of engine-recommended sanctions.
///
/// Displays pending [SanctionQueueItemView] cards backed by Supabase Realtime.
/// Every card exposes SELAR VEREDITO / RECUSAR VEREDITO / SOLICITAR PROVA FORENSE.
/// Satisfies INV-23: full VerdictEvidence provenance is shown per sanction.
class AuditorQueueScreen extends ConsumerWidget {
  const AuditorQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sanctionsAsync = ref.watch(pendingSanctionsStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(sanctionsAsync: sanctionsAsync),
          const SizedBox(height: 24),
          Expanded(
            child: sanctionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar fila: $e',
                  style: const TextStyle(color: VeraProbColors.error),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          SanctionVerdictCard(item: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dev Test Helper ───────────────────────────────────────────────────────────

/// Visible only in debug mode. Injects a synthetic VEL-01 sanction via the
/// [SanctionSimulationService] so testers can exercise the review flow without
/// needing Stress Mode or manual Studio inserts.
class _SimulateButton extends ConsumerStatefulWidget {
  const _SimulateButton();

  @override
  ConsumerState<_SimulateButton> createState() => _SimulateButtonState();
}

class _SimulateButtonState extends ConsumerState<_SimulateButton> {
  bool _loading = false;

  Future<void> _simulate() async {
    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Organização não encontrada. Faça login novamente.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(sanctionSimulationServiceProvider)
          .simulateSpeedViolation(
            organizationId: orgId,
            vehiclePlate: 'TST-0001',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao simular: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _simulate,
      icon: _loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.science_outlined, size: 16),
      label: const Text('Gerar Sanção de Teste'),
      style: OutlinedButton.styleFrom(
        foregroundColor: VeraProbColors.textSecondary,
        side: const BorderSide(color: VeraProbColors.textDisabled),
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AsyncValue<List<SanctionQueueItemView>> sanctionsAsync;
  const _Header({required this.sanctionsAsync});

  @override
  Widget build(BuildContext context) {
    final count = sanctionsAsync.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    return Row(
      children: [
        const Icon(Icons.gavel_rounded, color: VeraProbColors.primary),
        const SizedBox(width: 12),
        Text('Tribunal de Auditoria', style: VeraProbTypography.sectionTitle),
        const SizedBox(width: 12),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VeraProbColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count pendente${count > 1 ? 's' : ''}',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.error,
              ),
            ),
          ),
        const Spacer(),
        const _SimulateButton(),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.gavel_outlined,
            size: 56,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum veredito pendente',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Todos os vereditos foram selados ou recusados.',
            style: TextStyle(color: VeraProbColors.textDisabled),
          ),
          const SizedBox(height: 24),
          const _SimulateButton(),
        ],
      ),
    );
  }
}
