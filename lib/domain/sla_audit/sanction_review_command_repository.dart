import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';

/// Port for the atomic INITIAL verdict write path (approve / reject of a pending
/// sanction).
///
/// Backed by the `approve_sanction` / `reject_sanction` SECURITY DEFINER RPCs,
/// which migrate concurrency control and atomicity into the database: a single
/// transaction row-locks the queue entry, re-checks its `pending` status
/// (closing the TOCTOU race that let two auditors append duplicate VERDICT
/// facts), appends the verdict ledger fact (INV-3 append-only), and flips the
/// queue status. Collapses the former non-atomic round-trips into one.
///
/// On a concurrent double-review, the losing caller observes a non-pending
/// status after acquiring the lock and the implementation raises
/// `IdempotencyProcessingException` — no second ledger fact is ever appended.
///
/// **Reviewer identity:** [reviewedByUserId] is bound to the JWT `sub` claim by
/// the RPC (a mismatch is rejected) — a client cannot attribute a verdict to
/// another user. In-memory mode reuses the same value so both backends record an
/// identical `operator_id`.
// pr_scanner: ignore-regression — new additive port, no existing domain contract modified (Council-approved)
abstract class SanctionReviewCommandRepository {
  /// Seals a recommended sanction (`pending → applied`, `VERDICT_SEALED`).
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  });

  /// Refuses a recommended sanction (`pending → rejected`, `VERDICT_REFUSED`).
  ///
  /// [rejectionReason] is mandatory; the RPC fails closed on an empty reason.
  Future<SanctionReviewResult> rejectSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required DateTime occurredAtUtc,
  });
}
