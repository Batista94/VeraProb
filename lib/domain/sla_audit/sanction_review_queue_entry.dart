import 'package:equatable/equatable.dart';

import 'verdict_evidence.dart';

/// Possible review states for a sanction queue entry.
enum SanctionReviewStatus { pending, applied, rejected, disputed }

/// Entity representing a pending human review of an engine-recommended sanction.
///
/// Implements **Human-in-the-Loop** for INV-23: the engine RECOMMENDS,
/// auditors APPROVE. No `SANCTION_APPLIED` ever enters the ledger without
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
  });

  SanctionReviewQueueEntry copyWith({
    SanctionReviewStatus? status,
    DateTime? reviewedAtUtc,
    String? reviewedByUserId,
    String? rejectionReason,
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
      reviewedAtUtc: reviewedAtUtc ?? this.reviewedAtUtc,
      reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  @override
  List<Object?> get props => [id];
}
