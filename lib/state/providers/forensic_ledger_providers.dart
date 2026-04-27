import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/projections/forensic_ledger_view.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_ledger_projection.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

// ── ROI Guardian (Phase 10) ────────────────────────────────────────────────────

class RoiSummary {
  final int recoveredTrips;
  final int totalRecoveredCents; // INV-4: BIGINT cents
  final int totalAvoidedPenaltyCents; // INV-4: BIGINT cents
  final int totalLinkedTrips;
  final int pendingOrphans;
  final int? toolCostCents; // INV-4: NULL = not configured → ROI N/A
  final int? roiBps; // INV-5: basis points (10000 = 100%)

  const RoiSummary({
    required this.recoveredTrips,
    required this.totalRecoveredCents,
    required this.totalAvoidedPenaltyCents,
    required this.totalLinkedTrips,
    required this.pendingOrphans,
    this.toolCostCents,
    this.roiBps,
  });

  factory RoiSummary.fromRow(Map<String, dynamic> row) {
    return RoiSummary(
      recoveredTrips: (row['recovered_trips'] as int?) ?? 0,
      totalRecoveredCents: (row['total_recovered_cents'] as int?) ?? 0,
      totalAvoidedPenaltyCents:
          (row['total_avoided_penalty_cents'] as int?) ?? 0,
      totalLinkedTrips: (row['total_linked_trips'] as int?) ?? 0,
      pendingOrphans: (row['pending_orphans'] as int?) ?? 0,
      toolCostCents: row['tool_cost_cents'] as int?,
      roiBps: row['roi_bps'] as int?,
    );
  }
}

/// Streams ROI summary for the current org from v_roi_summary view.
/// INV-22: filters by organization_id (via RLS on shadow_executions base table).
final roiSummaryProvider = StreamProvider.autoDispose<RoiSummary?>((
  ref,
) async* {
  final client = ref.watch(supabaseClientProvider);
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) {
    yield null;
    return;
  }

  // Poll every 30s — v_roi_summary is a view, no realtime subscription needed
  while (true) {
    try {
      final data = await client
          .from('v_roi_summary')
          .select()
          .eq('organization_id', orgId)
          .maybeSingle();
      yield data != null ? RoiSummary.fromRow(data) : null;
    } catch (_) {
      yield null;
    }
    await Future<void>.delayed(const Duration(seconds: 30));
  }
});

/// Projection Provider for the Forensic Ledger.
///
/// Projects Domain entities into [ForensicLedgerEntry] DTOs,
/// sorted in reverse-chronological order (newest first).
final forensicLedgerProjectionProvider =
    StreamProvider<List<ForensicLedgerEntry>>((ref) {
      final mode = ref.watch(persistenceModeProvider);

      if (mode == PersistenceMode.postgres) {
        final client = ref.watch(supabaseClientProvider);
        return PostgresForensicLedgerProjection(client).watchLedger();
      }

      final repo = ref.watch(forensicDecisionRepositoryProvider);

      if (repo is InMemoryForensicRepository) {
        return repo.ledgerStream.map((decisions) {
          return decisions.reversed
              .map(
                (d) => ForensicLedgerEntry(
                  decisionId: d.decisionId,
                  actionType: d.actionType.key,
                  actionLabel: actionVerb(d.actionType.key),
                  actorId: d.actorId.value,
                  result: d.result.name.toUpperCase(),
                  reason: d.reason,
                  narrative: toNarrative(d),
                  timestamp: d.occurredAt,
                ),
              )
              .toList();
        });
      }

      return Stream.value([]);
    });
