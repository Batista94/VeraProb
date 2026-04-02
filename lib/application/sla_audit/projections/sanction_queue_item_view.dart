import '../../../domain/sla_audit/sanction_review_queue_entry.dart';
import '../../../domain/sla_audit/verdict_evidence.dart';

/// Read model projection for a single sanction queue item.
///
/// Contains display helpers to avoid raw data manipulation in the UI layer.
class SanctionQueueItemView {
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
      status: SanctionReviewStatus.values.byName(row['status'] as String),
      createdAtUtc: DateTime.parse(row['created_at'] as String),
      reviewedAtUtc: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String)
          : null,
      reviewedByUserId: row['reviewed_by'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
      vehiclePlate: row['vehicle_plate'] as String?,
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
    );
  }
}
