import 'package:equatable/equatable.dart';

/// Outcome of the atomic `dispute_sanction` transactional RPC.
///
/// The RPC performs lock → status re-check → ledger append → queue flip +
/// dispute provenance sealing in a single database transaction. This value
/// object captures the facts the application layer needs after the transaction
/// commits, with no partial-state ambiguity (INV-3).
// pr_scanner: ignore-regression — new additive VO, no existing domain contract modified (Council-approved)
class DisputeSanctionResult extends Equatable {
  /// ID of the `SANCTION_DISPUTED` ledger fact appended inside the transaction.
  final String ledgerEntryId;

  /// Final `sanction_review_queue.status` after the transition (`disputed`).
  final String finalQueueStatus;

  /// Computed SLA deadline (business-day based, INV-15).
  final DateTime resolutionDueAtUtc;

  const DisputeSanctionResult({
    required this.ledgerEntryId,
    required this.finalQueueStatus,
    required this.resolutionDueAtUtc,
  });

  factory DisputeSanctionResult.fromJson(Map<String, dynamic> json) {
    return DisputeSanctionResult(
      ledgerEntryId: json['ledger_entry_id'] as String,
      finalQueueStatus: json['status'] as String,
      resolutionDueAtUtc: DateTime.parse(json['resolution_due_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
    ledgerEntryId,
    finalQueueStatus,
    resolutionDueAtUtc,
  ];
}
