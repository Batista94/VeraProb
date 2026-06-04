import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [SanctionReviewQueueRepository].
///
/// **Architecture Guarantees:**
/// 1. **Idempotent enqueue**: Uses `ON CONFLICT DO NOTHING` on `uq_queue_ledger_entry` (INV-24).
/// 2. **Tenant isolation**: All queries scoped to `organization_id` (INV-6).
/// 3. **Status-only mutation**: DB trigger blocks updates to immutable fields (INV-1).
/// 4. **No delete**: No delete method exists on this class.
class PostgresSanctionReviewQueueRepository extends BasePostgresRepository
    implements SanctionReviewQueueRepository {
  PostgresSanctionReviewQueueRepository(super.client);

  @override
  Future<void> enqueue(SanctionReviewQueueEntry entry) async {
    try {
      await client
          .from('sanction_review_queue')
          .upsert(
            {
              'id': entry.id,
              'organization_id': entry.organizationId,
              'ledger_entry_id': entry.ledgerEntryId,
              'set_id': entry.setId,
              'contract_id': entry.contractId,
              'verdict_evidence': entry.verdictEvidence.toJson(),
              'status': entry.status.name,
              'created_at': entry.createdAtUtc.toIso8601String(),
            },
            onConflict: 'ledger_entry_id', // INV-24: idempotent
            ignoreDuplicates: true,
          );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sanction_review');
    }
  }

  @override
  Future<SanctionReviewQueueEntry?> findById(
    String id, {
    required String organizationId,
  }) async {
    try {
      final response = await client
          .from('sanction_review_queue')
          .select()
          .eq('id', id)
          .eq('organization_id', organizationId)
          .maybeSingle();

      if (response == null) return null;
      return _fromRow(response);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sanction_review');
    }
  }

  @override
  Future<List<SanctionReviewQueueEntry>> findPending({
    required String organizationId,
  }) async {
    try {
      final response = await client
          .from('sanction_review_queue')
          .select()
          .eq('organization_id', organizationId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return (response as List)
          .map((row) => _fromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sanction_review');
    }
  }

  @override
  Future<void> updateStatus(SanctionReviewQueueEntry entry) async {
    try {
      await client
          .from('sanction_review_queue')
          .update({
            'status': entry.status.name,
            'reviewed_at': entry.reviewedAtUtc?.toIso8601String(),
            'reviewed_by': entry.reviewedByUserId,
            'rejection_reason': entry.rejectionReason,
          })
          .eq('id', entry.id)
          .eq('organization_id', entry.organizationId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sanction_review');
    }
  }

  static SanctionReviewQueueEntry _fromRow(Map<String, dynamic> row) {
    return SanctionReviewQueueEntry(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      ledgerEntryId: row['ledger_entry_id'] as String,
      setId: row['set_id'] as String,
      contractId: row['contract_id'] as String,
      verdictEvidence: VerdictEvidence.fromJson(
        row['verdict_evidence'] as Map<String, dynamic>,
      ),
      status: IntegrityException.shield(
        SanctionReviewStatus.values,
        row['status'] as String,
        'status',
      ),
      createdAtUtc: DateTime.parse(row['created_at'] as String),
      reviewedAtUtc: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String)
          : null,
      reviewedByUserId: row['reviewed_by'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
      vehiclePlate: row['vehicle_plate'] as String?,
      operatorName: row['operator_name'] as String?,
    );
  }
}
