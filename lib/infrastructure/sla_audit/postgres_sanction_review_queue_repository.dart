import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/sanction_review_queue_entry.dart';
import '../../domain/sla_audit/sanction_review_queue_repository.dart';
import '../../domain/sla_audit/verdict_evidence.dart';

/// Postgres implementation of [SanctionReviewQueueRepository].
///
/// **Architecture Guarantees:**
/// 1. **Idempotent enqueue**: Uses `ON CONFLICT DO NOTHING` on `uq_queue_ledger_entry` (INV-24).
/// 2. **Tenant isolation**: All queries scoped to `organization_id` (INV-6).
/// 3. **Status-only mutation**: DB trigger blocks updates to immutable fields (INV-1).
/// 4. **No delete**: No delete method exists on this class.
class PostgresSanctionReviewQueueRepository
    implements SanctionReviewQueueRepository {
  final SupabaseClient _client;

  PostgresSanctionReviewQueueRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> enqueue(SanctionReviewQueueEntry entry) async {
    await _client.from('sanction_review_queue').upsert(
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
  }

  @override
  Future<SanctionReviewQueueEntry?> findById(
    String id, {
    required String organizationId,
  }) async {
    final response = await _client
        .from('sanction_review_queue')
        .select()
        .eq('id', id)
        .eq('organization_id', organizationId)
        .maybeSingle();

    if (response == null) return null;
    return _fromRow(response);
  }

  @override
  Future<List<SanctionReviewQueueEntry>> findPending({
    required String organizationId,
  }) async {
    final response = await _client
        .from('sanction_review_queue')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return (response as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> updateStatus(SanctionReviewQueueEntry entry) async {
    await _client
        .from('sanction_review_queue')
        .update({
          'status': entry.status.name,
          'reviewed_at': entry.reviewedAtUtc?.toIso8601String(),
          'reviewed_by': entry.reviewedByUserId,
          'rejection_reason': entry.rejectionReason,
        })
        .eq('id', entry.id)
        .eq('organization_id', entry.organizationId);
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
      status: SanctionReviewStatus.values.byName(row['status'] as String),
      createdAtUtc: DateTime.parse(row['created_at'] as String),
      reviewedAtUtc: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String)
          : null,
      reviewedByUserId: row['reviewed_by'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
    );
  }
}
