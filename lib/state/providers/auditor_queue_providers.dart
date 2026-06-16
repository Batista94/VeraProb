import 'package:flutter/foundation.dart' show listEquals, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_command.dart';
import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_handler.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_command.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/confirm_peer_review_command.dart';
import 'package:veraprob/application/sla_audit/confirm_peer_review_handler.dart';
import 'package:veraprob/application/sla_audit/decline_peer_review_command.dart';
import 'package:veraprob/application/sla_audit/decline_peer_review_handler.dart';
import 'package:veraprob/application/sla_audit/dispute_sanction_command.dart';
import 'package:veraprob/application/sla_audit/dispute_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_command.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/infraction_recurrence_report.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
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

/// Stream of disputed/waiting evidence sanction items for the current session's organization.
final disputedSanctionsStreamProvider =
    StreamProvider.autoDispose<List<SanctionQueueItemView>>((ref) {
      return ref
          .watch(supabaseClientProvider)
          .from('sanction_review_queue')
          .stream(primaryKey: ['id'])
          .eq('status', 'disputed')
          .map(
            (rows) =>
                rows.map((row) => SanctionQueueItemView.fromRow(row)).toList(),
          )
          .distinct(listEquals);
    });

/// Derived count of disputed sanctions.
final disputedSanctionsCountProvider = Provider.autoDispose<int>((ref) {
  final sanctionsAsync = ref.watch(disputedSanctionsStreamProvider);
  return switch (sanctionsAsync) {
    AsyncData(:final value) => value.length,
    AsyncError() => 0,
    AsyncLoading() => 0,
  };
});

/// Stream of items awaiting a SECOND auditor (dual-control hold lane).
final peerReviewSanctionsStreamProvider =
    StreamProvider.autoDispose<List<SanctionQueueItemView>>((ref) {
      return ref
          .watch(supabaseClientProvider)
          .from('sanction_review_queue')
          .stream(primaryKey: ['id'])
          .eq('status', 'pending_peer_review')
          .map(
            (rows) =>
                rows.map((row) => SanctionQueueItemView.fromRow(row)).toList(),
          )
          .distinct(listEquals);
    });

/// Derived count of items awaiting a second auditor.
final peerReviewSanctionsCountProvider = Provider.autoDispose<int>((ref) {
  final sanctionsAsync = ref.watch(peerReviewSanctionsStreamProvider);
  return switch (sanctionsAsync) {
    AsyncData(:final value) => value.length,
    AsyncError() => 0,
    AsyncLoading() => 0,
  };
});

// ── SLA aging: overdue / expiring disputes (Componente 4.6) ──────────────────

/// Disputes approaching their deadline are flagged this many days in advance.
const int kDisputeSlaWarningDays = 2;

/// Disputed items already PAST their `resolution_due_at` deadline.
///
/// Derived client-side from [disputedSanctionsStreamProvider] (the row already
/// carries `resolution_due_at`) — no extra query. Recomputes on every stream
/// emission; "now" is sampled per emission, which is precise enough for the
/// breach badge + drill-down.
final overdueDisputesProvider =
    Provider.autoDispose<List<SanctionQueueItemView>>((ref) {
      final now = DateTime.now().toUtc();
      return switch (ref.watch(disputedSanctionsStreamProvider)) {
        AsyncData(:final value) =>
          value
              .where(
                (i) =>
                    i.resolutionDueAtUtc != null &&
                    i.resolutionDueAtUtc!.isBefore(now),
              )
              .toList(),
        _ => const <SanctionQueueItemView>[],
      };
    });

/// Count of overdue disputes — drives the [SlaBreachBadge] (hidden when 0).
final overdueDisputesCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(overdueDisputesProvider).length,
);

/// Disputed items within [kDisputeSlaWarningDays] of the deadline but not yet
/// overdue — the amber "expiring soon" cohort.
final expiringDisputesProvider =
    Provider.autoDispose<List<SanctionQueueItemView>>((ref) {
      final now = DateTime.now().toUtc();
      final horizon = now.add(const Duration(days: kDisputeSlaWarningDays));
      return switch (ref.watch(disputedSanctionsStreamProvider)) {
        AsyncData(:final value) => value.where((i) {
          final due = i.resolutionDueAtUtc;
          return due != null && !due.isBefore(now) && due.isBefore(horizon);
        }).toList(),
        _ => const <SanctionQueueItemView>[],
      };
    });

// ── Retraction provenance enrichment (INV-23) ────────────────────────────────

/// Who cancelled a dispute and when, read from the latest `DISPUTE_RETRACTED`
/// ledger fact. The queue row keeps `disputed_by`/`disputed_at` (who opened —
/// never cleared), but the canceller lives only in the fact.
typedef RetractionProvenance = ({
  String? retractedBy,
  DateTime? retractedAtUtc,
});

/// Lazily resolves the retraction fact for a queue item that returned to
/// `pending` after a retract. Null when no retraction fact exists. RLS scopes
/// the ledger read to the caller's org.
final disputeRetractionProvenanceProvider = FutureProvider.autoDispose
    .family<RetractionProvenance?, String>((ref, queueEntryId) async {
      final row = await ref
          .watch(supabaseClientProvider)
          .from('sla_audit_ledger_v2')
          .select('payload, occurred_at_utc')
          .eq('type', 'DISPUTE_RETRACTED')
          .eq('payload->>queue_entry_id', queueEntryId)
          .order('occurred_at_utc', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final payload = row['payload'] as Map<String, dynamic>?;
      final occurred = row['occurred_at_utc'] as String?;
      return (
        retractedBy: payload?['retracted_by_user_id'] as String?,
        retractedAtUtc: occurred == null
            ? null
            : DateTime.parse(occurred).toUtc(),
      );
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
    reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
    rbac: RbacService(),
  );

  AcknowledgeSanctionInternalHandler get _acknowledgeInternalHandler =>
      AcknowledgeSanctionInternalHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
        ackRepo: ref.watch(sanctionAcknowledgementCommandRepositoryProvider),
        rbac: RbacService(),
      );

  RejectSanctionHandler get _rejectHandler => RejectSanctionHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
    reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
    rbac: RbacService(),
    clock: ref.watch(dateTimeProviderProvider),
  );

  DisputeSanctionHandler get _disputeHandler => DisputeSanctionHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
    reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
    rbac: RbacService(),
  );

  ResolveDisputeHandler get _resolveDisputeHandler => ResolveDisputeHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
    resolutionRepo: ref.watch(sanctionDisputeResolutionRepositoryProvider),
    rbac: RbacService(),
    dateTimeProvider: ref.watch(dateTimeProviderProvider),
  );

  ConfirmPeerReviewHandler get _confirmPeerReviewHandler =>
      ConfirmPeerReviewHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
        reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
        rbac: RbacService(),
        clock: ref.watch(dateTimeProviderProvider),
      );

  DeclinePeerReviewHandler get _declinePeerReviewHandler =>
      DeclinePeerReviewHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
        reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
        rbac: RbacService(),
        clock: ref.watch(dateTimeProviderProvider),
      );

  Future<void> dispute({
    required String queueEntryId,
    required String disputedByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _disputeHandler.handle(
        DisputeSanctionCommand(
          queueEntryId: queueEntryId,
          disputedByUserId: disputedByUserId,
          actorEmail: actorEmail,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  Future<void> resolveDispute({
    required String queueEntryId,
    required DisputeResolution resolution,
    required String resolvedByUserId,
    required String actorEmail,
    String? resolutionReason,
    String? reasonCode,
    List<String> evidenceIds = const [],
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _resolveDisputeHandler.handle(
        ResolveDisputeCommand(
          queueEntryId: queueEntryId,
          resolution: resolution,
          resolvedByUserId: resolvedByUserId,
          actorEmail: actorEmail,
          resolutionReason: resolutionReason,
          reasonCode: reasonCode,
          evidenceIds: evidenceIds,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

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
    required String reasonCode,
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
          reasonCode: reasonCode,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  /// Dual-control: the SECOND auditor confirms a high-value verdict held in
  /// `pending_peer_review`. The handler propagates
  /// `DualControlSelfApprovalException` if [confirmedByUserId] is the requester.
  Future<void> confirmPeerReview({
    required String queueEntryId,
    required String confirmedByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _confirmPeerReviewHandler.handle(
        ConfirmPeerReviewCommand(
          queueEntryId: queueEntryId,
          confirmedByUserId: confirmedByUserId,
          actorEmail: actorEmail,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  /// Dual-control: decline a `pending_peer_review` item, reverting it to its
  /// origin status. Permitted to any auditor (incl. the first reviewer).
  Future<void> declinePeerReview({
    required String queueEntryId,
    required String declinedByUserId,
    required String actorEmail,
    required String reason,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _declinePeerReviewHandler.handle(
        DeclinePeerReviewCommand(
          queueEntryId: queueEntryId,
          declinedByUserId: declinedByUserId,
          actorEmail: actorEmail,
          reason: reason,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  /// Records an off-band "De Acordo" (carrier accepted the penalty via
  /// email/phone) for an `applied` sanction. TENANT_ADMIN-only; flips the entry
  /// to the terminal `acknowledged` status server-side.
  Future<void> acknowledgeInternal({
    required String queueEntryId,
    required String acknowledgedByUserId,
    String? notes,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    await guardedAction(
      () => _acknowledgeInternalHandler.handle(
        AcknowledgeSanctionInternalCommand(
          queueEntryId: queueEntryId,
          acknowledgedByUserId: acknowledgedByUserId,
          notes: notes,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );
  }
}

// ── Filter and Sealed Sanctions Pagination (Enterprise Hardening) ───────────

enum AuditorQueueFilter { pending, disputed, sealed, acknowledged }

class AuditorQueueFilterNotifier extends Notifier<AuditorQueueFilter> {
  @override
  AuditorQueueFilter build() => AuditorQueueFilter.pending;

  void setFilter(AuditorQueueFilter value) => state = value;
}

/// Provider managing the active filter state for the Auditor Queue.
final auditorQueueFilterProvider =
    NotifierProvider.autoDispose<
      AuditorQueueFilterNotifier,
      AuditorQueueFilter
    >(AuditorQueueFilterNotifier.new);

/// When true, the `disputed` lane shows ONLY overdue items (resolution_due_at <
/// now). Toggled on by the [SlaBreachBadge] drill-down; reset when the auditor
/// changes the segmented filter.
class DisputeOverdueOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final disputeOverdueOnlyProvider =
    NotifierProvider.autoDispose<DisputeOverdueOnlyNotifier, bool>(
      DisputeOverdueOnlyNotifier.new,
    );

class SealedSanctionsState {
  final List<SanctionQueueItemView> items;
  final bool isLoading;
  final bool hasMore;
  final DateTime startDate;
  final DateTime endDate;

  const SealedSanctionsState({
    required this.items,
    required this.isLoading,
    required this.hasMore,
    required this.startDate,
    required this.endDate,
  });

  SealedSanctionsState copyWith({
    List<SanctionQueueItemView>? items,
    bool? isLoading,
    bool? hasMore,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return SealedSanctionsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

/// Terminal sanction lanes — both append-only end states that grow unbounded,
/// so each is paginated + date-filtered (never a live realtime stream).
/// [statuses] maps a lane to the `status` values it surfaces.
enum TerminalLane {
  /// Sealed verdicts: `applied` (fine upheld) + `rejected` (fine refused).
  verdicts(['applied', 'rejected']),

  /// "De Acordo": carrier-acknowledged penalties (off-band acceptance).
  acknowledged(['acknowledged']);

  const TerminalLane(this.statuses);

  final List<String> statuses;
}

class SealedSanctionsNotifier extends Notifier<SealedSanctionsState> {
  SealedSanctionsNotifier(this.lane);

  final TerminalLane lane;

  static const int _pageSize = 20;

  @override
  SealedSanctionsState build() {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 7));
    // Initial fetch scheduled for post-build to avoid ref.read during build
    Future.microtask(() => fetchNextPage(clear: true));

    return SealedSanctionsState(
      items: const [],
      isLoading: false,
      hasMore: true,
      startDate: start,
      endDate: now,
    );
  }

  Future<void> updateDateFilter(DateTime start, DateTime end) async {
    state = state.copyWith(
      startDate: start,
      endDate: end,
      items: const [],
      hasMore: true,
    );
    await fetchNextPage(clear: true);
  }

  Future<void> fetchNextPage({bool clear = false}) async {
    if (state.isLoading || (!clear && !state.hasMore)) return;

    state = state.copyWith(isLoading: true);

    try {
      final client = ref.read(supabaseClientProvider);
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      final offset = clear ? 0 : state.items.length;

      final rows = await client
          .from('sanction_review_queue')
          .select()
          .eq('organization_id', orgId)
          .inFilter('status', lane.statuses)
          .gte('created_at', state.startDate.toIso8601String())
          .lte('created_at', state.endDate.toIso8601String())
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final newItems = (rows as List)
          .map(
            (row) => SanctionQueueItemView.fromRow(row as Map<String, dynamic>),
          )
          .toList();

      state = state.copyWith(
        items: clear ? newItems : [...state.items, ...newItems],
        isLoading: false,
        hasMore: newItems.length == _pageSize,
      );
    } catch (e, stack) {
      state = state.copyWith(isLoading: false);
      // INV-26: do not expose internal error details directly
      debugPrint('[SealedSanctionsNotifier] Error: $e\n$stack');
    }
  }
}

final sealedSanctionsNotifierProvider = NotifierProvider.autoDispose
    .family<SealedSanctionsNotifier, SealedSanctionsState, TerminalLane>(
      SealedSanctionsNotifier.new,
    );

// ── Simulation wrapper (state layer — features must not import domain) ────────

/// Calls [SanctionSimulationService.simulateSpeedViolation] and converts
/// any exception to a human-readable message so features never import
/// from the domain layer directly (INV-13).
///
/// Returns null on success. Returns an error message string on any failure
/// (both [DomainException] and unexpected infra/DB errors). Callers must
/// treat null as the ONLY success signal.
Future<String?> runSanctionSimulation(
  WidgetRef ref, {
  required String organizationId,
  required String vehiclePlate,
}) async {
  try {
    await ref
        .read(sanctionSimulationServiceProvider)
        .simulateSpeedViolation(
          organizationId: organizationId,
          vehiclePlate: vehiclePlate,
        );
    return null;
  } on DomainException catch (e) {
    return e.message;
  } catch (_) {
    return 'Não foi possível simular a sanção. Verifique se há contratos ativos.';
  }
}
