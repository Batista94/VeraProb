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
  ///
  /// [reasonCode] is OPTIONAL (sealing affirms the engine's verdict). When
  /// supplied it must be an active key of the closed `dispute_reason_codes`
  /// taxonomy — the RPC fails closed on an unknown code. [reviewerReason] is an
  /// optional free-text complement. Both are recorded in the `VERDICT_SEALED`
  /// ledger fact for verdict explainability (INV-21/INV-23).
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    String? reasonCode,
    String? reviewerReason,
  });

  /// Refuses a recommended sanction (`pending → rejected`, `VERDICT_REFUSED`).
  ///
  /// [rejectionReason] is mandatory; the RPC fails closed on an empty reason.
  /// [reasonCode] is a mandatory key from the closed `dispute_reason_codes`
  /// taxonomy; the RPC fails closed on an unknown/inactive code.
  Future<SanctionReviewResult> rejectSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required String reasonCode,
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

  /// Mints a single-use, TTL-bounded carrier portal token for a contested
  /// sanction, backed by the `generate_dispute_portal_token` SECURITY DEFINER
  /// RPC. The entry must belong to [organizationId] and be `disputed`/`applied`;
  /// the RPC appends a `DISPUTE_PORTAL_TOKEN_GENERATED` ledger fact.
  ///
  /// Returns the opaque UUID token; the caller builds the portal URL
  /// (`/portal/dispute?token=<uuid>`) and hands it to the carrier.
  Future<String> generateDisputePortalToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
  });

  /// Mints a submit-scoped token allowing a carrier to upload counter-evidence.
  /// Backed by the `generate_portal_submit_token` SECURITY DEFINER RPC.
  ///
  /// Requires the sanction to be strictly `disputed`. Returns the opaque UUID token.
  Future<String> generatePortalSubmitToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
  });
}
