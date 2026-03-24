import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/approve_sanction_command.dart';
import '../../application/sla_audit/approve_sanction_handler.dart';
import '../../application/sla_audit/projections/sanction_queue_item_view.dart';
import '../../application/sla_audit/reject_sanction_command.dart';
import '../../application/sla_audit/reject_sanction_handler.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/services/rbac_service.dart';
import '../../infrastructure/sla_audit/sla_persistence_provider.dart';

// ── Realtime stream of pending sanctions ─────────────────────────────────────

/// Stream of all pending sanction items for the current session's organization.
/// Backed by Supabase Realtime — updates arrive in <30s (INV-23 notification SLA).
///
/// RLS enforces tenant isolation; no explicit org_id filter needed in query.
final pendingSanctionsStreamProvider =
    StreamProvider.autoDispose<List<SanctionQueueItemView>>((ref) {
      return Supabase.instance.client
          .from('sanction_review_queue')
          .stream(primaryKey: ['id'])
          .eq('status', 'pending')
          .map(
            (rows) =>
                rows.map((row) => SanctionQueueItemView.fromRow(row)).toList(),
          );
    });

// ── Derived badge count ───────────────────────────────────────────────────────

/// Derived count of pending sanctions for the navigation badge.
final pendingSanctionsCountProvider = Provider.autoDispose<int>((ref) {
  return ref
      .watch(pendingSanctionsStreamProvider)
      .maybeWhen(data: (items) => items.length, orElse: () => 0);
});

// ── Contract name enrichment ──────────────────────────────────────────────────

/// Resolves the human-readable contract name for a given [contractId].
///
/// Returns null if the contract is not found (RLS will silently block
/// cross-tenant access — no explicit error exposed to the UI).
final contractNameProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, contractId) async {
    final row = await Supabase.instance.client
        .from('contracts')
        .select('name')
        .eq('id', contractId)
        .maybeSingle();
    return row?['name'] as String?;
  },
);

// ── Per-sanction action state ─────────────────────────────────────────────────

/// Loading/error state for approve/reject actions on a specific sanction card.
/// Key: queueEntryId.
final sanctionActionStateProvider = StateNotifierProvider.autoDispose
    .family<SanctionActionNotifier, AsyncValue<void>, String>(
      (ref, sanctionId) => SanctionActionNotifier(
        approveHandler: ApproveSanctionHandler(
          queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          rbac: RbacService(),
        ),
        rejectHandler: RejectSanctionHandler(
          queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          rbac: RbacService(),
        ),
      ),
    );

class SanctionActionNotifier extends StateNotifier<AsyncValue<void>> {
  final ApproveSanctionHandler _approveHandler;
  final RejectSanctionHandler _rejectHandler;

  SanctionActionNotifier({
    required ApproveSanctionHandler approveHandler,
    required RejectSanctionHandler rejectHandler,
  }) : _approveHandler = approveHandler,
       _rejectHandler = rejectHandler,
       super(const AsyncData(null));

  Future<void> approve({
    required String queueEntryId,
    required String approvedByUserId,
    required UserRole callerRole,
    required String organizationId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _approveHandler.handle(
        ApproveSanctionCommand(
          queueEntryId: queueEntryId,
          approvedByUserId: approvedByUserId,
          callerRole: callerRole,
          organizationId: organizationId,
        ),
      ),
    );
  }

  Future<void> reject({
    required String queueEntryId,
    required String rejectedByUserId,
    required String rejectionReason,
    required UserRole callerRole,
    required String organizationId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _rejectHandler.handle(
        RejectSanctionCommand(
          queueEntryId: queueEntryId,
          rejectedByUserId: rejectedByUserId,
          rejectionReason: rejectionReason,
          callerRole: callerRole,
          organizationId: organizationId,
        ),
      ),
    );
  }
}
