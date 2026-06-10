import 'package:equatable/equatable.dart';

/// Outcome of the atomic `approve_sanction` / `reject_sanction` transactional RPC.
///
/// The RPC performs lock → status re-check → ledger append → queue flip in a
/// single database transaction. This value object captures the two facts the
/// application layer needs after the transaction commits, with no partial-state
/// ambiguity (INV-3).
// pr_scanner: ignore-regression — new additive VO, no existing domain contract modified (Council-approved)
class SanctionReviewResult extends Equatable {
  /// ID of the verdict ledger fact appended inside the transaction
  /// (`VERDICT_SEALED` for approve / `VERDICT_REFUSED` for reject).
  final String ledgerEntryId;

  /// Final `sanction_review_queue.status` after the transition
  /// (`applied` / `rejected`).
  final String finalQueueStatus;

  const SanctionReviewResult({
    required this.ledgerEntryId,
    required this.finalQueueStatus,
  });

  factory SanctionReviewResult.fromJson(Map<String, dynamic> json) {
    return SanctionReviewResult(
      ledgerEntryId: json['ledger_entry_id'] as String,
      finalQueueStatus: json['status'] as String,
    );
  }

  @override
  List<Object?> get props => [ledgerEntryId, finalQueueStatus];
}
