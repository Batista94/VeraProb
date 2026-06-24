import 'package:equatable/equatable.dart';

/// Outcome of the atomic `resolve_dispute` transactional RPC.
///
/// The RPC performs lock → status re-check → ledger append → queue update →
/// (overturn only) inline snapshot seal in a single database transaction. This
/// value object captures the three facts the application layer needs after the
/// transaction commits, with no partial-state ambiguity (INV-3, INV-21).
// pr_scanner: ignore-regression — new additive VO, no existing domain contract modified (Council-approved)
class DisputeResolutionResult extends Equatable {
  /// ID of the resolution ledger fact appended inside the transaction
  /// (`DISPUTE_ACCEPTED` / `DISPUTE_OVERTURNED` / `DISPUTE_RETRACTED`).
  final String ledgerEntryId;

  /// Final `sanction_review_queue.status` after the transition
  /// (`rejected` / `applied` / `pending`).
  final String finalQueueStatus;

  /// The sealed forensic snapshot, present only for the overturn arc
  /// (INV-21). Null for accept/retract.
  final Map<String, dynamic>? snapshot;

  /// Verified SHA-256 hashes of the evidence embedded in the resolution fact,
  /// when the RPC surfaces them. Null when the transaction returns none.
  final List<String>? evidenceHashes;

  const DisputeResolutionResult({
    required this.ledgerEntryId,
    required this.finalQueueStatus,
    this.snapshot,
    this.evidenceHashes,
  });

  factory DisputeResolutionResult.fromJson(Map<String, dynamic> json) {
    final snapshotOpt = json['snapshot'];
    final hashesOpt = json['evidence_hashes'];
    return DisputeResolutionResult(
      ledgerEntryId: json['ledger_entry_id'] as String,
      finalQueueStatus: json['status'] as String,
      snapshot: snapshotOpt != null
          ? Map<String, dynamic>.from(snapshotOpt as Map)
          : null,
      evidenceHashes: hashesOpt != null
          ? (hashesOpt as List).map((e) => e as String).toList()
          : null,
    );
  }

  @override
  List<Object?> get props => [
    ledgerEntryId,
    finalQueueStatus,
    snapshot,
    evidenceHashes,
  ];
}
