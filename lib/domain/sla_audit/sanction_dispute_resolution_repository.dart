import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';

/// Port for the atomic dispute-resolution write path.
///
/// Backed by the `resolve_dispute` SECURITY DEFINER RPC, which migrates
/// concurrency control and atomicity into the database: a single transaction
/// row-locks the queue entry, re-checks its `disputed` status (closing the
/// TOCTOU race), appends the resolution ledger fact (INV-3 append-only), flips
/// the queue status, and — for the overturn arc — seals the forensic snapshot
/// inline (INV-21). Collapses the former 3–4 non-atomic round-trips into one.
///
/// On a concurrent double-resolution, the losing caller observes a non-disputed
/// status after acquiring the lock and the implementation raises
/// `IdempotencyProcessingException` — no second ledger fact is ever appended.
// pr_scanner: ignore-regression — new additive port, no existing domain contract modified (Council-approved)
abstract class SanctionDisputeResolutionRepository {
  /// Resolves a disputed sanction atomically.
  ///
  /// [resolution] is the already-computed ledger fact type
  /// (`DISPUTE_ACCEPTED` / `DISPUTE_OVERTURNED` / `DISPUTE_RETRACTED`); the
  /// domain state-machine mapping stays in the application layer so no business
  /// rule is duplicated in SQL.
  Future<DisputeResolutionResult> resolveDispute({
    required String organizationId,
    required String queueEntryId,
    required String resolution,
    required String? resolutionReason,
    required String? reasonCode,
    required String resolvedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    required String idempotencyKey,
  });
}
