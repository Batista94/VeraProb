import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/features/admin/presentation/widgets/sla_breach_badge.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/telemetry_sync_map.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue/widgets/auditor_header.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue/widgets/auditor_empty_state.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue/widgets/auditor_filter_bars.dart';

/// Responsive breakpoint: below this width, the map becomes a Drawer.
const _kMapBreakpoint = 1200.0;

/// Ordering for the `disputed` lane. A card whose carrier already submitted a
/// defense (`defenseSubmittedAt != null`) is the one actually awaiting the
/// auditor's verdict, so it floats to the top ("DEFESA RECEBIDA"). Among peers
/// with the same defense state, the soonest `resolutionDueAtUtc` (SLA deadline)
/// comes first; rows without a deadline sink to the bottom. Pure + total so it
/// can be unit-tested in isolation (Bug 2-A regression guard).
int compareDisputedLane(SanctionQueueItemView a, SanctionQueueItemView b) {
  if (a.defenseSubmittedAt != null && b.defenseSubmittedAt == null) return -1;
  if (a.defenseSubmittedAt == null && b.defenseSubmittedAt != null) return 1;
  if (a.resolutionDueAtUtc == null && b.resolutionDueAtUtc == null) return 0;
  if (a.resolutionDueAtUtc == null) return 1;
  if (b.resolutionDueAtUtc == null) return -1;
  return a.resolutionDueAtUtc!.compareTo(b.resolutionDueAtUtc!);
}

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
            AuditorHeader(
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
      return AsyncValueWidget(
        asyncValue: sanctionsAsync,
        loading: () => const SkeletonListLoader(),
        data: (value) => value.isEmpty
            ? const AuditorEmptyState()
            : PanelContainer(
                child: ListView.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => SanctionVerdictCard(item: value[i]),
                ),
              ),
      );
    } else if (filter == AuditorQueueFilter.disputed) {
      final sanctionsAsync = ref.watch(disputedSanctionsStreamProvider);
      final overdueOnly = ref.watch(disputeOverdueOnlyProvider);
      final now = DateTime.now().toUtc();
      return AsyncValueWidget(
        asyncValue: sanctionsAsync,
        loading: () => const SkeletonListLoader(),
        data: (value) => _buildDisputedList(
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
      );
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
          DateFilterBar(lane: lane),
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
                : PanelContainer(
                    child: ListView.separated(
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
                : 'Nenhuma sanção em disputa.',
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
        ),
      );
    }

    final sortedItems = List<SanctionQueueItemView>.from(items)
      ..sort(compareDisputedLane);

    final list = PanelContainer(
      child: ListView.separated(
        itemCount: sortedItems.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => SanctionVerdictCard(item: sortedItems[i]),
      ),
    );

    if (!overdueOnly) return list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverdueFilterBanner(
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
