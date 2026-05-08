import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/approve_sanction_command.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_command.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/infraction_recurrence_report.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/notifiers/async_command_mixin.dart';
import 'auth_providers.dart';
import 'contract_providers.dart';
import 'shared_providers.dart';
import 'sla_providers.dart';

// ── Realtime stream of pending sanctions ─────────────────────────────────────

/// Stream of all pending sanction items for the current session's organization.
/// Backed by Supabase Realtime — updates arrive in <30s (INV-23 notification SLA).
///
/// RLS enforces tenant isolation; no explicit org_id filter needed in query.
/// INV-30: Client injected via supabaseClientProvider (no Supabase.instance).
///
/// Uses [Stream.distinct] with [listEquals] to filter consecutive duplicate
/// emissions. Since [SanctionQueueItemView] extends [Equatable], element-wise
/// comparison via `==` correctly identifies identical lists, ensuring Riverpod
/// v3's default `updateShouldNotify` (which relies on `==`) does not trigger
/// unnecessary listener rebuilds (Req 8.1, 8.4).
final pendingSanctionsStreamProvider =
    StreamProvider.autoDispose<List<SanctionQueueItemView>>((ref) {
      return ref
          .watch(supabaseClientProvider)
          .from('sanction_review_queue')
          .stream(primaryKey: ['id'])
          .eq('status', 'pending')
          .map(
            (rows) =>
                rows.map((row) => SanctionQueueItemView.fromRow(row)).toList(),
          )
          .distinct(listEquals);
    });

// ── Derived badge count ───────────────────────────────────────────────────────

/// Derived count of pending sanctions for the navigation badge.
final pendingSanctionsCountProvider = Provider.autoDispose<int>((ref) {
  final sanctionsAsync = ref.watch(pendingSanctionsStreamProvider);
  return switch (sanctionsAsync) {
    AsyncData(:final value) => value.length,
    AsyncError() => 0,
    AsyncLoading() => 0,
  };
});

// ── Contract name enrichment ──────────────────────────────────────────────────

/// Resolves the human-readable contract name for a given [contractId].
///
/// Returns null if the contract is not found (RLS will silently block
/// cross-tenant access — no explicit error exposed to the UI).
/// INV-30: Client injected via supabaseClientProvider.
final contractNameProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, contractId) async {
    final row = await ref
        .watch(supabaseClientProvider)
        .from('contracts')
        .select('name')
        .eq('id', contractId)
        .maybeSingle();
    return row?['name'] as String?;
  },
);

// ── SLA window enrichment ─────────────────────────────────────────────────────

/// Resolves the original SLA window (start + end) for a sanction queue item
/// identified by [setId].
///
/// Returns null if the execution state is not found or RLS blocks access.
/// Follows the same lazy-enrichment pattern as [contractNameProvider].
final sanctionWindowProvider = FutureProvider.autoDispose
    .family<({DateTime start, DateTime end})?, String>((ref, setId) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return null;

      final service = ref.watch(slaExecutionQueryServiceProvider);
      final item = await service.findBySetId(
        setId,
        organizationId: organizationId,
      );
      if (item == null) return null;

      return (start: item.windowStartUtc, end: item.windowEndUtc);
    });

// ── Vehicle infraction recurrence ─────────────────────────────────────────────

/// Computes the monthly recurrence context for a vehicle plate.
///
/// Key format: "$queueEntryId|$vehiclePlate|$organizationId"
///
/// Returns null when [vehiclePlate] is empty (no plate = no recurrence context).
final vehicleInfractionRecurrenceProvider = FutureProvider.autoDispose
    .family<InfractionRecurrenceReport?, String>((ref, key) async {
      final parts = key.split('|');
      if (parts.length != 3 || parts[1].isEmpty) return null;
      final service = VehicleInfractionRecurrenceService(
        repository: ref.watch(vehicleInfractionRecurrenceRepositoryProvider),
      );
      return service.computeRecurrence(
        organizationId: parts[2],
        vehiclePlate: parts[1],
        referenceUtc: DateTime.now().toUtc(),
        currentQueueEntryId: parts[0],
      );
    });

// ── Per-sanction action state ─────────────────────────────────────────────────

/// Loading/error state for approve/reject actions on a specific sanction card.
/// Key: queueEntryId.
final sanctionActionStateProvider = NotifierProvider.autoDispose
    .family<SanctionActionNotifier, AsyncValue<void>, String>(
      SanctionActionNotifier.new,
    );

class SanctionActionNotifier extends Notifier<AsyncValue<void>>
    with GuardedAsyncActionMixin<void> {
  SanctionActionNotifier(this.sanctionId);
  final String sanctionId;

  @override
  AsyncValue<void> build() {
    return const AsyncData(null);
  }

  ApproveSanctionHandler get _approveHandler => ApproveSanctionHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    rbac: RbacService(),
  );

  RejectSanctionHandler get _rejectHandler => RejectSanctionHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    rbac: RbacService(),
    clock: ref.watch(dateTimeProviderProvider),
  );

  Future<void> approve({
    required String queueEntryId,
    required String approvedByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _approveHandler.handle(
        ApproveSanctionCommand(
          queueEntryId: queueEntryId,
          approvedByUserId: approvedByUserId,
          actorEmail: actorEmail,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  Future<void> reject({
    required String queueEntryId,
    required String rejectedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _rejectHandler.handle(
        RejectSanctionCommand(
          queueEntryId: queueEntryId,
          rejectedByUserId: rejectedByUserId,
          actorEmail: actorEmail,
          rejectionReason: rejectionReason,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }
}
