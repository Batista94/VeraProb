import 'package:veraprob/domain/sla_audit/dispute_sanction_result.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';

/// Port for the atomic INITIAL verdict write path (approve / reject / dispute
/// of a pending sanction).
///
/// Backed by the `approve_sanction` / `reject_sanction` / `dispute_sanction`
/// SECURITY DEFINER RPCs, which migrate concurrency control and atomicity into
/// the database: a single transaction row-locks the queue entry, re-checks its
/// `pending` status (closing the TOCTOU race that let two auditors append
/// duplicate VERDICT facts), appends the verdict ledger fact (INV-3 append-only),
/// and flips the queue status. Collapses the former non-atomic round-trips into
/// one.
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

  /// Confirms a high-value verdict held in `pending_peer_review`, applying the
  /// recorded proposed action terminally (dual-control / four-eyes).
  ///
  /// [reviewedByUserId] is the SECOND auditor (bound to the JWT `sub`). The RPC
  /// raises `DualControlSelfApprovalException` if it equals the first reviewer —
  /// reviewer2 != reviewer1 is enforced server-side, not by the client.
  Future<SanctionReviewResult> confirmPeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  });

  /// Declines a `pending_peer_review` item, reverting it to its origin status
  /// (`pending` or `disputed`). Permitted to any auditor, including the first
  /// reviewer withdrawing their own request.
  Future<SanctionReviewResult> declinePeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String reason,
    required DateTime occurredAtUtc,
  });

  /// Transitions a pending sanction to `disputed` atomically.
  ///
  /// Seals `disputed_at`, `disputed_by`, and `resolution_due_at` inline inside
  /// the DB transaction. The SLA deadline is computed server-side using
  /// `_resolve_dispute_sla_days` + `_compute_business_day_deadline` (INV-15).
  ///
  /// Throws [IdempotencyProcessingException] if the entry is no longer pending.
  Future<DisputeSanctionResult> disputeSanction({
    required String organizationId,
    required String queueEntryId,
    required String disputedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  });
}
