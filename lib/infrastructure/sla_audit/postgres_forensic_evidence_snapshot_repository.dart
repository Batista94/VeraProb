import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [ForensicEvidenceSnapshotRepository].
///
/// **Architecture guarantees:**
/// - [seal] delegates to the `seal_forensic_evidence` SECURITY DEFINER RPC — the
///   sole, atomic write path (Req 5/10). No direct table INSERT exists here.
/// - Reads are tenant-scoped (`organization_id` filter) and rely on RLS for
///   404-parity (INV-26): a cross-tenant lookup returns null.
/// - No update/delete (INV-3 — append-only vault).
class PostgresForensicEvidenceSnapshotRepository extends BasePostgresRepository
    implements ForensicEvidenceSnapshotRepository {
  PostgresForensicEvidenceSnapshotRepository(super.client);

  static const _columns =
      'id, organization_id, ledger_entry_id, contract_id, rule_set_id, '
      'sla_rule_version, schema_version, effective_from_utc, effective_to_utc, '
      'snapshot, integrity_hash, sealed_by, sealed_at_utc';

  @override
  Future<ForensicEvidenceSnapshot> seal({
    required String organizationId,
    required String contractId,
    required String setId,
    required String verdictType,
    required int planVersion,
    required DateTime occurredAtUtc,
    required String sealedBy,
    required String idempotencyKey,
  }) {
    return withErrorHandler('forensic_evidence_snapshot', null, () async {
      final result = await client.rpc<Map<String, dynamic>>(
        'seal_forensic_evidence',
        params: {
          'p_organization_id': organizationId,
          'p_contract_id': contractId,
          'p_set_id': setId,
          'p_verdict_type': verdictType,
          'p_plan_version': planVersion,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
          'p_sealed_by': sealedBy,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return ForensicEvidenceSnapshot.fromJson(result);
    });
  }

  @override
  Future<ForensicEvidenceSnapshot> sealForDispute({
    required String organizationId,
    required String ledgerEntryId,
    required String contractId,
    required String setId,
    required int planVersion,
    required DateTime occurredAtUtc,
    required String sealedBy,
    required String idempotencyKey,
  }) {
    return withErrorHandler(
      'forensic_evidence_snapshot',
      ledgerEntryId,
      () async {
        final result = await client.rpc<Map<String, dynamic>>(
          'seal_dispute_resolution_snapshot',
          params: {
            'p_organization_id': organizationId,
            'p_ledger_entry_id': ledgerEntryId,
            'p_contract_id': contractId,
            'p_set_id': setId,
            'p_plan_version': planVersion,
            'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
            'p_sealed_by': sealedBy,
            'p_idempotency_key': idempotencyKey,
          },
        );
        return ForensicEvidenceSnapshot.fromJson(result);
      },
    );
  }

  @override
  Future<ForensicEvidenceSnapshot?> findByLedgerEntry({
    required String organizationId,
    required String ledgerEntryId,
  }) async {
    try {
      return await withErrorHandler(
        'forensic_evidence_snapshot',
        ledgerEntryId,
        () async {
          final row = await client
              .from('forensic_evidence_snapshots')
              .select(_columns)
              .eq('organization_id', organizationId)
              .eq('ledger_entry_id', ledgerEntryId)
              .maybeSingle();
          if (row == null) return null;
          return ForensicEvidenceSnapshot.fromJson(row);
        },
      );
    } on ResourceNotFoundException {
      return null;
    }
  }

  @override
  Future<List<ForensicEvidenceSnapshot>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  }) {
    return withErrorHandler(
      'forensic_evidence_snapshot',
      organizationId,
      () async {
        final rows = await client
            .from('forensic_evidence_snapshots')
            .select(_columns)
            .eq('organization_id', organizationId)
            .gte('sealed_at_utc', fromUtc.toUtc().toIso8601String())
            .lte('sealed_at_utc', toUtc.toUtc().toIso8601String())
            .order('sealed_at_utc', ascending: false)
            .limit(limit);
        return (rows as List)
            .map(
              (r) =>
                  ForensicEvidenceSnapshot.fromJson(r as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  @override
  Future<EvidenceVerification> verify({
    required String organizationId,
    required String ledgerEntryId,
  }) {
    return withErrorHandler(
      'forensic_evidence_snapshot',
      ledgerEntryId,
      () async {
        final snapshot = await findByLedgerEntry(
          organizationId: organizationId,
          ledgerEntryId: ledgerEntryId,
        );
        if (snapshot == null) {
          throw ResourceNotFoundException(
            resourceType: 'forensic_evidence_snapshot',
            resourceId: ledgerEntryId,
          );
        }

        final result = await client.rpc<Map<String, dynamic>>(
          'verify_forensic_evidence',
          params: {
            'p_organization_id': organizationId,
            'p_ledger_entry_id': ledgerEntryId,
          },
        );

        final storedHash = result['stored_hash'] as String;
        final computedHash = result['computed_hash'] as String;
        final status = result['status'] == 'authentic'
            ? EvidenceVerificationStatus.authentic
            : EvidenceVerificationStatus.tampered;

        if (status == EvidenceVerificationStatus.tampered) {
          throw IntegrityException(
            'Forensic snapshot integrity check failed for verdict $ledgerEntryId '
            '(stored=$storedHash computed=$computedHash). Potential tampering.',
            field: 'integrity_hash',
          );
        }

        return EvidenceVerification(
          ledgerEntryId: ledgerEntryId,
          status: status,
          storedHash: storedHash,
          computedHash: computedHash,
          snapshot: snapshot,
        );
      },
    );
  }
}
