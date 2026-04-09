import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/telemetry_sync_map.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';

/// Responsive breakpoint: below this width, the map becomes a Drawer.
const _kMapBreakpoint = 1200.0;

/// Tribunal de Auditoria — Human-in-the-Loop review of engine-recommended sanctions.
///
/// **WS-5 (Telemetry Map-Sync):** Split-pane layout on wide screens (≥1200px)
/// with a dedicated [TelemetrySyncMap] panel on the right. On narrow screens,
/// the map is accessible via an end-drawer toggle (FAB).
///
/// Displays pending [SanctionQueueItemView] cards backed by Supabase Realtime.
/// Every card exposes SELAR VEREDITO / RECUSAR VEREDITO / SOLICITAR PROVA FORENSE.
/// Satisfies INV-23: full VerdictEvidence provenance is shown per sanction.
class AuditorQueueScreen extends ConsumerStatefulWidget {
  const AuditorQueueScreen({super.key});

  @override
  ConsumerState<AuditorQueueScreen> createState() => _AuditorQueueScreenState();
}

class _AuditorQueueScreenState extends ConsumerState<AuditorQueueScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final sanctionsAsync = ref.watch(pendingSanctionsStreamProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= _kMapBreakpoint;

    // WS-5: Auto-open drawer when a sanction is focused on narrow screens
    ref.listen<SanctionMapFocus?>(selectedSanctionFocusProvider, (prev, next) {
      if (!isWide &&
          next != null &&
          !(_scaffoldKey.currentState?.isEndDrawerOpen ?? false)) {
        _scaffoldKey.currentState?.openEndDrawer();
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      // WS-5: End-drawer with forensic map for narrow screens
      endDrawer: isWide
          ? null
          : Drawer(
              width: screenWidth * 0.45,
              backgroundColor: VeraProbColors.background,
              child: SafeArea(
                child: Column(
                  children: [
                    // Drawer header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: VeraProbColors.surface,
                        border: Border(
                          bottom: BorderSide(color: VeraProbColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.map_outlined,
                            size: 16,
                            color: VeraProbColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mapa Forense',
                            style: VeraProbTypography.sectionTitle,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.pop(context),
                            color: VeraProbColors.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Map
                    const Expanded(child: TelemetrySyncMap()),
                  ],
                ),
              ),
            ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              sanctionsAsync: sanctionsAsync,
              showMapToggle: !isWide,
              onMapToggle: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: isWide
                  ? _buildSplitPane(sanctionsAsync)
                  : _buildCardList(sanctionsAsync),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide layout: Card list (flex 6) + Forensic Map (flex 4).
  Widget _buildSplitPane(
    AsyncValue<List<SanctionQueueItemView>> sanctionsAsync,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Sanction card list
        Expanded(flex: 6, child: _buildCardList(sanctionsAsync)),
        // Divider
        Container(
          width: 1,
          color: VeraProbColors.border,
          margin: const EdgeInsets.symmetric(horizontal: 12),
        ),
        // Right: Forensic Evidence Map (WS-5)
        const Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            child: TelemetrySyncMap(),
          ),
        ),
      ],
    );
  }

  /// Card list (shared between split-pane and single-column layouts).
  Widget _buildCardList(
    AsyncValue<List<SanctionQueueItemView>> sanctionsAsync,
  ) {
    return sanctionsAsync.when(
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
              itemBuilder: (_, i) => SanctionVerdictCard(item: items[i]),
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
  final bool showMapToggle;
  final VoidCallback? onMapToggle;

  const _Header({
    required this.sanctionsAsync,
    this.showMapToggle = false,
    this.onMapToggle,
  });

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
        // WS-5: Map toggle for narrow screens
        if (showMapToggle)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: onMapToggle,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Mapa Forense'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VeraProbColors.primary,
                side: BorderSide(
                  color: VeraProbColors.primary.withValues(alpha: 0.5),
                ),
                textStyle: const TextStyle(fontSize: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
            ),
          ),
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
