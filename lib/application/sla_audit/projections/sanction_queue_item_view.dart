import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';

/// Read model projection for a single sanction queue item.
///
/// Contains display helpers to avoid raw data manipulation in the UI layer.
///
/// Extends [Equatable] so that Riverpod v3's default `updateShouldNotify`
/// (which uses `==`) can correctly filter duplicate stream emissions.
/// Only semantically-relevant fields from the DB row are included in [props];
/// UI-enriched fields ([contractName], [windowStartUtc], [windowEndUtc]) are
/// excluded because they are resolved asynchronously and do not represent
/// identity of the queue item.
class SanctionQueueItemView extends Equatable {
  final String id;
  final String organizationId;
  final String ledgerEntryId;
  final String setId;
  final String contractId;
  final VerdictEvidence verdictEvidence;
  final SanctionReviewStatus status;
  final DateTime createdAtUtc;
  final DateTime? reviewedAtUtc;
  final String? reviewedByUserId;
  final String? rejectionReason;

  /// Human-readable contract name resolved asynchronously from the UI layer.
  /// Null until enriched via [contractNameProvider]. Never stored in the DB row.
  final String? contractName;

  /// Original SLA window start resolved asynchronously from the UI layer.
  /// Null until enriched via [sanctionWindowProvider]. Never stored in the DB row.
  final DateTime? windowStartUtc;

  /// Original SLA deadline resolved asynchronously from the UI layer.
  /// Null until enriched via [sanctionWindowProvider]. Never stored in the DB row.
  final DateTime? windowEndUtc;

  /// Denormalized vehicle plate from the DB row (see INV-1 trigger).
  /// Null for legacy rows or unbound vehicles.
  final String? vehiclePlate;

  /// Denormalized operator (driver) name from the DB row (INV-14).
  /// Null when telemetry arrived without an authenticated operator.
  final String? operatorName;

  /// Dual-control (Phase 10.5 Item 2): first reviewer of a high-value verdict
  /// held in `pending_peer_review`. The confirming auditor must differ.
  final String? firstReviewerId;

  /// Proposed terminal action awaiting a second auditor
  /// (`APPROVE`/`REJECT`/`OVERTURN`/`DISPUTE_ACCEPT`).
  final String? peerReviewProposedAction;

  /// TTL deadline after which the peer review reverts to its origin status.
  final DateTime? peerReviewExpiresAtUtc;

  /// When the dispute was opened (`pending → disputed`). Sealed once at open
  /// (INV-15). NEVER cleared — survives a retract so provenance stays auditable
  /// (INV-23). A `pending` item carrying a non-null [disputedAtUtc] was disputed
  /// and later retracted.
  final DateTime? disputedAtUtc;

  /// Actor who opened the dispute. NEVER cleared on retract (INV-23).
  final String? disputedBy;

  /// Business-day deadline to resolve the dispute (Componente 3 SLA timer).
  /// Drives the [DisputeSlaChip] countdown / overdue signal on disputed cards.
  final DateTime? resolutionDueAtUtc;

  /// Transport-agnostic alias for the bound asset identifier (INV-14).
  /// Today resolves to the vehicle plate; stays stable if the asset model
  /// generalizes beyond road vehicles.
  String? get assetIdentifier => vehiclePlate;

  const SanctionQueueItemView({
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
    this.contractName,
    this.windowStartUtc,
    this.windowEndUtc,
    this.vehiclePlate,
    this.operatorName,
    this.firstReviewerId,
    this.peerReviewProposedAction,
    this.peerReviewExpiresAtUtc,
    this.disputedAtUtc,
    this.disputedBy,
    this.resolutionDueAtUtc,
  });

  /// Formatted fine amount as BRL string (e.g., "R$ 1.500,00").
  String get formattedFine {
    final value = verdictEvidence.fineCents.cents / 100.0;
    final whole = value.floor();
    final decimal = ((value - whole) * 100).round().toString().padLeft(2, '0');
    return 'R\$ ${_formatThousands(whole)},$decimal';
  }

  /// Short display of evidence hash (first 12 chars).
  String get shortEvidenceHash => verdictEvidence.evidenceHash.substring(0, 12);

  /// Confidence score as percentage string.
  String get formattedConfidence => '${verdictEvidence.confidenceScore}%';

  static String _formatThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Builds a [SanctionQueueItemView] from a Supabase row map.
  factory SanctionQueueItemView.fromRow(Map<String, dynamic> row) {
    return SanctionQueueItemView(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      ledgerEntryId: row['ledger_entry_id'] as String,
      setId: row['set_id'] as String,
      contractId: row['contract_id'] as String,
      verdictEvidence: VerdictEvidence.fromJson(
        row['verdict_evidence'] as Map<String, dynamic>,
      ),
      status: SanctionReviewStatusDb.fromDbValue(row['status'] as String),
      createdAtUtc: DateTime.parse(row['created_at'] as String),
      reviewedAtUtc: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String)
          : null,
      reviewedByUserId: row['reviewed_by'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
      vehiclePlate: row['vehicle_plate'] as String?,
      operatorName: row['operator_name'] as String?,
      firstReviewerId: row['first_reviewer_id'] as String?,
      peerReviewProposedAction: row['peer_review_proposed_action'] as String?,
      peerReviewExpiresAtUtc: row['peer_review_expires_at'] != null
          ? DateTime.parse(row['peer_review_expires_at'] as String)
          : null,
      disputedAtUtc: row['disputed_at'] != null
          ? DateTime.parse(row['disputed_at'] as String)
          : null,
      disputedBy: row['disputed_by'] as String?,
      resolutionDueAtUtc: row['resolution_due_at'] != null
          ? DateTime.parse(row['resolution_due_at'] as String)
          : null,
    );
  }

  factory SanctionQueueItemView.fromEntry(SanctionReviewQueueEntry entry) {
    return SanctionQueueItemView(
      id: entry.id,
      organizationId: entry.organizationId,
      ledgerEntryId: entry.ledgerEntryId,
      setId: entry.setId,
      contractId: entry.contractId,
      verdictEvidence: entry.verdictEvidence,
      status: entry.status,
      createdAtUtc: entry.createdAtUtc,
      reviewedAtUtc: entry.reviewedAtUtc,
      reviewedByUserId: entry.reviewedByUserId,
      rejectionReason: entry.rejectionReason,
      vehiclePlate: entry.vehiclePlate,
      operatorName: entry.operatorName,
      firstReviewerId: entry.firstReviewerId,
      peerReviewProposedAction: entry.peerReviewProposedAction,
      peerReviewExpiresAtUtc: entry.peerReviewExpiresAtUtc,
    );
  }

  /// Semantically-relevant fields for value equality.
  ///
  /// UI-enriched fields ([contractName], [windowStartUtc], [windowEndUtc]) are
  /// intentionally excluded — they are resolved lazily and do not define the
  /// identity of a queue item from the DB perspective.
  @override
  List<Object?> get props => [
    id,
    organizationId,
    ledgerEntryId,
    setId,
    contractId,
    verdictEvidence,
    status,
    createdAtUtc,
    reviewedAtUtc,
    reviewedByUserId,
    rejectionReason,
    vehiclePlate,
    operatorName,
    firstReviewerId,
    peerReviewProposedAction,
    peerReviewExpiresAtUtc,
    disputedAtUtc,
    disputedBy,
    resolutionDueAtUtc,
  ];
}
