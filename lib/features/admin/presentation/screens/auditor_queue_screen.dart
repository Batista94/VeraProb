import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/features/admin/presentation/widgets/sla_breach_badge.dart';
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
              child: isWide ? _buildSplitPane(ref) : _buildCardList(ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide layout: Card list (flex 6) + Forensic Map (flex 4).
  Widget _buildSplitPane(WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Sanction card list
        Expanded(flex: 6, child: _buildCardList(ref)),
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
  Widget _buildCardList(WidgetRef ref) {
    final filter = ref.watch(auditorQueueFilterProvider);
    if (filter == AuditorQueueFilter.pending) {
      final sanctionsAsync = ref.watch(pendingSanctionsStreamProvider);
      return switch (sanctionsAsync) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(
          child: Text(
            'Erro ao carregar fila: $error',
            style: const TextStyle(color: VeraProbColors.error),
          ),
        ),
        AsyncData(:final value) =>
          value.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => SanctionVerdictCard(item: value[i]),
                ),
      };
    } else if (filter == AuditorQueueFilter.disputed) {
      final sanctionsAsync = ref.watch(disputedSanctionsStreamProvider);
      final overdueOnly = ref.watch(disputeOverdueOnlyProvider);
      final now = DateTime.now().toUtc();
      return switch (sanctionsAsync) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(
          child: Text(
            'Erro ao carregar fila: $error',
            style: const TextStyle(color: VeraProbColors.error),
          ),
        ),
        AsyncData(:final value) => _buildDisputedList(
          ref,
          overdueOnly
              ? value
                    .where(
                      (i) =>
                          i.resolutionDueAtUtc != null &&
                          i.resolutionDueAtUtc!.isBefore(now),
                    )
                    .toList()
              : value,
          overdueOnly: overdueOnly,
        ),
      };
    } else {
      final lane = filter == AuditorQueueFilter.acknowledged
          ? TerminalLane.acknowledged
          : TerminalLane.verdicts;
      final sealedState = ref.watch(sealedSanctionsNotifierProvider(lane));
      final emptyMessage = lane == TerminalLane.acknowledged
          ? 'Nenhuma penalidade em "De Acordo" neste período.'
          : 'Nenhum veredito selado encontrado neste período.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateFilterBar(lane: lane),
          const SizedBox(height: 12),
          Expanded(
            child: sealedState.items.isEmpty && !sealedState.isLoading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        emptyMessage,
                        style: const TextStyle(
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount:
                        sealedState.items.length +
                        (sealedState.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == sealedState.items.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: sealedState.isLoading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: () => ref
                                        .read(
                                          sealedSanctionsNotifierProvider(
                                            lane,
                                          ).notifier,
                                        )
                                        .fetchNextPage(),
                                    child: const Text('CARREGAR MAIS'),
                                  ),
                          ),
                        );
                      }
                      return SanctionVerdictCard(item: sealedState.items[i]);
                    },
                  ),
          ),
        ],
      );
    }
  }

  /// Renders the `disputed` lane, optionally narrowed to the overdue cohort by
  /// the [SlaBreachBadge] drill-down. When the drill-down is active a dismissible
  /// banner makes the implicit filter explicit (Lesson #5: no silent state).
  Widget _buildDisputedList(
    WidgetRef ref,
    List<SanctionQueueItemView> items, {
    required bool overdueOnly,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            overdueOnly
                ? 'Nenhuma disputa vencida.'
                : 'Nenhuma sanção aguardando evidência.',
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
        ),
      );
    }

    final list = ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => SanctionVerdictCard(item: items[i]),
    );

    if (!overdueOnly) return list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverdueFilterBanner(
          count: items.length,
          onClear: () =>
              ref.read(disputeOverdueOnlyProvider.notifier).set(false),
        ),
        const SizedBox(height: 12),
        Expanded(child: list),
      ],
    );
  }
}

// ── Overdue drill-down banner ─────────────────────────────────────────────────

/// Explicit indicator that the `disputed` lane is filtered to overdue items
/// only (via the [SlaBreachBadge]). Tapping clears the filter back to all
/// disputes.
class _OverdueFilterBanner extends StatelessWidget {
  final int count;
  final VoidCallback onClear;

  const _OverdueFilterBanner({required this.count, required this.onClear});

  @override
  Widget build(BuildContext context) {
    const red = VeraProbColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_outlined, size: 16, color: red),
          const SizedBox(width: 10),
          Text(
            'Filtrando $count disputa(s) com SLA vencido',
            style: const TextStyle(fontSize: 12, color: red),
          ),
          const Spacer(),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: red,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('LIMPAR'),
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
  final bool isNarrow;
  const _SimulateButton({this.isNarrow = false});

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
      final error = await runSanctionSimulation(
        ref,
        organizationId: orgId,
        vehiclePlate: 'TST-0001',
      );
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: VeraProbColors.error),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível simular a sanção. Verifique se há contratos ativos.',
            ),
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
    if (widget.isNarrow) {
      return Tooltip(
        message: 'Gerar Sanção de Teste',
        child: OutlinedButton(
          onPressed: _loading ? null : _simulate,
          style: OutlinedButton.styleFrom(
            foregroundColor: VeraProbColors.textSecondary,
            side: const BorderSide(color: VeraProbColors.textDisabled),
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(36, 36),
          ),
          child: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.science_outlined, size: 16),
        ),
      );
    }
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

class _Header extends ConsumerWidget {
  final AsyncValue<List<SanctionQueueItemView>> sanctionsAsync;
  final bool showMapToggle;
  final VoidCallback? onMapToggle;

  const _Header({
    required this.sanctionsAsync,
    this.showMapToggle = false,
    this.onMapToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(auditorQueueFilterProvider);
    final count = switch (sanctionsAsync) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };
    final disputedCount = switch (ref.watch(disputedSanctionsStreamProvider)) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // Lesson #3: narrow panel — short labels + tooltip on segments
        final isNarrow = constraints.maxWidth < 900;
        return Row(
          children: [
            const Icon(Icons.gavel_rounded, color: VeraProbColors.primary),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Tribunal de Auditoria',
                style: VeraProbTypography.sectionTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),

            // Segmented filter toggle — Expanded prevents right overflow
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<AuditorQueueFilter>(
                  segments: [
                    ButtonSegment<AuditorQueueFilter>(
                      value: AuditorQueueFilter.pending,
                      // Lesson #3: short label on narrow, full label on wide
                      label: isNarrow
                          ? Tooltip(
                              message: 'Pendentes ($count)',
                              child: Text('($count)'),
                            )
                          : Text('Pendentes ($count)'),
                      icon: const Icon(
                        Icons.pending_actions_outlined,
                        size: 14,
                      ),
                    ),
                    ButtonSegment<AuditorQueueFilter>(
                      value: AuditorQueueFilter.disputed,
                      label: isNarrow
                          ? Tooltip(
                              message: 'Aguardando Evidência ($disputedCount)',
                              child: Text('($disputedCount)'),
                            )
                          : Text('Aguardando Evidência ($disputedCount)'),
                      icon: const Icon(
                        Icons.hourglass_empty_outlined,
                        size: 14,
                      ),
                    ),
                    ButtonSegment<AuditorQueueFilter>(
                      value: AuditorQueueFilter.sealed,
                      label: isNarrow
                          ? const Tooltip(
                              message: 'Concluídos',
                              child: SizedBox.shrink(),
                            )
                          : const Text('Concluídos'),
                      icon: const Icon(Icons.verified_user_outlined, size: 14),
                    ),
                    ButtonSegment<AuditorQueueFilter>(
                      value: AuditorQueueFilter.acknowledged,
                      label: isNarrow
                          ? const Tooltip(
                              message: 'De Acordo',
                              child: SizedBox.shrink(),
                            )
                          : const Text('De Acordo'),
                      icon: const Icon(Icons.handshake_outlined, size: 14),
                    ),
                  ],
                  selected: {filter},
                  onSelectionChanged: (newSelection) {
                    // Manual filter change clears the breach-badge drill-down.
                    ref.read(disputeOverdueOnlyProvider.notifier).set(false);
                    ref
                        .read(auditorQueueFilterProvider.notifier)
                        .setFilter(newSelection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: VeraProbColors.primary.withValues(
                      alpha: 0.15,
                    ),
                    selectedForegroundColor: VeraProbColors.primary,
                    foregroundColor: VeraProbColors.textSecondary,
                    side: const BorderSide(color: VeraProbColors.border),
                  ),
                ),
              ),
            ),

            const Spacer(),
            // WS-5: Map toggle for narrow screens
            if (showMapToggle)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Mapa Forense',
                  child: OutlinedButton.icon(
                    onPressed: onMapToggle,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: isNarrow
                        ? const SizedBox.shrink()
                        : const Text('Mapa Forense'),
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
              ),
            const SlaBreachBadge(),
            _SimulateButton(isNarrow: isNarrow),
          ],
        );
      },
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

// ── Date Filter Bar ───────────────────────────────────────────────────────────

class _DateFilterBar extends ConsumerWidget {
  final TerminalLane lane;
  const _DateFilterBar({required this.lane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sealedSanctionsNotifierProvider(lane));
    String format(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.date_range_outlined,
            size: 16,
            color: VeraProbColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(
            'Período: ${format(state.startDate.toLocal())} até ${format(state.endDate.toLocal())}',
            style: VeraProbTypography.bodySmall,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(
                  start: state.startDate,
                  end: state.endDate,
                ),
                firstDate: DateTime(2025),
                lastDate: DateTime.now().toUtc().add(const Duration(days: 1)),
              );
              if (picked != null) {
                await ref
                    .read(sealedSanctionsNotifierProvider(lane).notifier)
                    .updateDateFilter(picked.start, picked.end);
              }
            },
            icon: const Icon(Icons.edit_calendar_outlined, size: 14),
            label: const Text('ALTERAR'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
