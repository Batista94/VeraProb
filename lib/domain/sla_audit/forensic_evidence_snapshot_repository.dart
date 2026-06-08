import 'forensic_evidence_snapshot.dart';

/// Outcome of an on-read integrity verification (Req 8).
enum EvidenceVerificationStatus { authentic, tampered }

/// Result of recomputing a snapshot hash and comparing it to the sealed value.
class EvidenceVerification {
  final String ledgerEntryId;
  final EvidenceVerificationStatus status;
  final String storedHash;
  final String computedHash;
  final ForensicEvidenceSnapshot snapshot;

  const EvidenceVerification({
    required this.ledgerEntryId,
    required this.status,
    required this.storedHash,
    required this.computedHash,
    required this.snapshot,
  });

  bool get isAuthentic => status == EvidenceVerificationStatus.authentic;
}

/// Port for the Forensic Evidence Vault.
///
/// **Architecture guarantees:**
/// - [seal] is the sole write path, delegating to the Backend-Authority RPC.
///   Idempotent on (organizationId, idempotencyKey) — replay returns the existing
///   snapshot without a second verdict (INV-11, Req 6/10.4).
/// - All reads are tenant-scoped via [organizationId] (INV-1, INV-22).
/// - No update/delete operation exists (INV-3 — append-only vault).
abstract class ForensicEvidenceSnapshotRepository {
  /// Seals a verdict: atomically appends the ledger entry, freezes the active
  /// SLA rule, computes the integrity hash and persists the snapshot.
  ///
  /// [verdictType] is the ledger verdict classification (e.g. 'NO_SHOW_PENALTY').
  /// [setId] is the obligation identifier the verdict pertains to.
  Future<ForensicEvidenceSnapshot> seal({
    required String organizationId,
    required String contractId,
    required String setId,
    required String verdictType,
    required int planVersion,
    required DateTime occurredAtUtc,
    required String sealedBy,
    required String idempotencyKey,
  });

  /// Seals a forensic snapshot for an existing DISPUTE_OVERTURNED ledger entry.
  ///
  /// Unlike [seal], this method does NOT append a new ledger entry (INV-3).
  /// It links the snapshot to [ledgerEntryId] — the entry already appended by
  /// [ResolveDisputeHandler] — and computes the integrity hash identically so
  /// [verify] works without modification.
  Future<ForensicEvidenceSnapshot> sealForDispute({
    required String organizationId,
    required String ledgerEntryId,
    required String contractId,
    required String setId,
    required int planVersion,
    required DateTime occurredAtUtc,
    required String sealedBy,
    required String idempotencyKey,
  });

  /// Returns the snapshot bound to a verdict, or null if none exists for this
  /// tenant (cross-tenant / unknown → null, 404 parity per INV-26).
  Future<ForensicEvidenceSnapshot?> findByLedgerEntry({
    required String organizationId,
    required String ledgerEntryId,
  });

  /// Returns snapshots for an org sealed within the given UTC range, newest first.
  Future<List<ForensicEvidenceSnapshot>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  });

  /// Recomputes and compares the integrity hash for a sealed verdict (Req 8).
  Future<EvidenceVerification> verify({
    required String organizationId,
    required String ledgerEntryId,
  });
}
