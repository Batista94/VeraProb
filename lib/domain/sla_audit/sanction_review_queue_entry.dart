// pr_scanner: ignore-regression — Sprint A (Portal + De Acordo), council-approved
// plan `convoque-o-conselho-de-linear-diffie`: adds the terminal `acknowledged`
// status. Append-only enum extension; no existing state semantics altered.
import 'package:equatable/equatable.dart';

import 'verdict_evidence.dart';

/// Possible review states for a sanction queue entry.
///
/// [pendingPeerReview] is the dual-control (four-eyes) holding state: a verdict
/// whose fine exceeds the resolved threshold waits here for a SECOND, DISTINCT
/// auditor to confirm or decline (Phase 10.5, Item 2).
enum SanctionReviewStatus {
  pending,
  applied,
  rejected,
  disputed,
  pendingPeerReview,

  /// Terminal "De Acordo": the carrier (or an internal record) formally accepted
  /// the applied penalty. No transition out (sealed by `prevent_srq_immutable_mutation`).
  /// Drives the AR "Pending Acknowledgement" → settled signal (Sprint A, M4).
  acknowledged,
}

/// Entity representing a pending human review of an engine-recommended sanction.
///
/// Implements **Human-in-the-Loop** for INV-23: the engine RECOMMENDS,
/// auditors APPROVE. No `VERDICT_SEALED` ever enters the ledger without
/// explicit human action.
///
/// **Identity:** equality is based exclusively on [id].
class SanctionReviewQueueEntry extends Equatable {
  final String id;
  final String organizationId;

  /// FK → sla_audit_ledger_v2.id for the SANCTION_RECOMMENDED entry.
  /// Immutable after creation (INV-1 on the DB trigger).
  final String ledgerEntryId;

  final String setId;
  final String contractId;
  final VerdictEvidence verdictEvidence;
  final SanctionReviewStatus status;
  final DateTime createdAtUtc;
  final DateTime? reviewedAtUtc;
  final String? reviewedByUserId;
  final String? rejectionReason;

  /// Denormalized vehicle plate, resolved at INSERT time by the DB trigger
  /// (migration 20260610000001_srq_vehicle_plate.sql). Nullable — unbound
  /// vehicles or legacy rows may not have a plate.
  ///
  /// Excluded from [props]: identity is [id]-based, not plate-based.
  final String? vehiclePlate;

  /// Denormalized operator (driver) name, resolved at INSERT time by the DB
  /// trigger (migration 20260805000002_srq_operator_name.sql). Nullable —
  /// telemetry may arrive without an authenticated operator (INV-14).
  final String? operatorName;

  /// Dual-control (Phase 10.5, Item 2). Populated only while [status] is
  /// [SanctionReviewStatus.pendingPeerReview].

  /// JWT sub of the auditor who requested the high-value verdict. The confirm
  /// RPC rejects a second reviewer whose JWT sub equals this (reviewer2 != 1).
  final String? firstReviewerId;

  /// Proposed terminal action awaiting a second auditor:
  /// `APPROVE` | `REJECT` | `OVERTURN` | `DISPUTE_ACCEPT`.
  final String? peerReviewProposedAction;

  /// Status to revert to on decline/expiry (`pending` or `disputed`).
  final String? peerReviewOriginStatus;

  /// When the pending peer review lapses and reverts to origin (TTL).
  final DateTime? peerReviewExpiresAtUtc;

  const SanctionReviewQueueEntry({
    required this.id,
    required this.organizationId,
    required this.ledgerEntryId,
    required this.setId,
    required this.contractId,
    required this.verdictEvidence,
    required this.status,
    required this.createdAtUtc,
    this.reviewedAtUtc,
    this.reviewedByUserId,
    this.rejectionReason,
    this.vehiclePlate,
    this.operatorName,
    this.firstReviewerId,
    this.peerReviewProposedAction,
    this.peerReviewOriginStatus,
    this.peerReviewExpiresAtUtc,
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable review fields cannot be cleared by passing `null` (the
  /// `?? this.x` fallback would preserve the old value). To null them — as the
  /// dispute *retract* arc requires (`disputed → pending` must wipe the prior
  /// review) — pass the matching `clear*` flag. A `clear*` flag always wins
  /// over a positional value for the same field.
  SanctionReviewQueueEntry copyWith({
    SanctionReviewStatus? status,
    DateTime? reviewedAtUtc,
    String? reviewedByUserId,
    String? rejectionReason,
    String? firstReviewerId,
    String? peerReviewProposedAction,
    String? peerReviewOriginStatus,
    DateTime? peerReviewExpiresAtUtc,
    bool clearReviewedAtUtc = false,
    bool clearReviewedByUserId = false,
    bool clearRejectionReason = false,
    bool clearPeerReview = false,
  }) {
    return SanctionReviewQueueEntry(
      id: id,
      organizationId: organizationId,
      ledgerEntryId: ledgerEntryId,
      setId: setId,
      contractId: contractId,
      verdictEvidence: verdictEvidence,
      status: status ?? this.status,
      createdAtUtc: createdAtUtc,
      reviewedAtUtc: clearReviewedAtUtc
          ? null
          : (reviewedAtUtc ?? this.reviewedAtUtc),
      reviewedByUserId: clearReviewedByUserId
          ? null
          : (reviewedByUserId ?? this.reviewedByUserId),
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? this.rejectionReason),
      vehiclePlate: vehiclePlate,
      operatorName: operatorName,
      firstReviewerId: clearPeerReview
          ? null
          : (firstReviewerId ?? this.firstReviewerId),
      peerReviewProposedAction: clearPeerReview
          ? null
          : (peerReviewProposedAction ?? this.peerReviewProposedAction),
      peerReviewOriginStatus: clearPeerReview
          ? null
          : (peerReviewOriginStatus ?? this.peerReviewOriginStatus),
      peerReviewExpiresAtUtc: clearPeerReview
          ? null
          : (peerReviewExpiresAtUtc ?? this.peerReviewExpiresAtUtc),
    );
  }

  @override
  List<Object?> get props => [id];
}

/// DB ⇄ domain mapping for [SanctionReviewStatus].
///
/// Every status maps to its `.name` EXCEPT [SanctionReviewStatus.pendingPeerReview],
/// which is stored snake_case (`pending_peer_review`) to match the DB CHECK
/// constraint `chk_srq_status`.
extension SanctionReviewStatusDb on SanctionReviewStatus {
  String get dbValue => this == SanctionReviewStatus.pendingPeerReview
      ? 'pending_peer_review'
      : name;

  static SanctionReviewStatus fromDbValue(String value) =>
      value == 'pending_peer_review'
      ? SanctionReviewStatus.pendingPeerReview
      : SanctionReviewStatus.values.byName(value);
}
