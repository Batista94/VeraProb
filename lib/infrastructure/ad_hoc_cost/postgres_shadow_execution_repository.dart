import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/ad_hoc_cost/shadow_execution.dart';
import 'package:veraprob/domain/ad_hoc_cost/shadow_execution_status.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation for shadow_executions ad-hoc cost objects.
///
/// INV-1:  All queries filter by organization_id.
/// INV-3:  No DELETE. Status transitions guarded by DB trigger.
/// INV-22: RLS enforces tenant isolation at DB level.
/// INV-26: Not-found and wrong-org return null (identical shape, anti-oracle).
class PostgresShadowExecutionRepository extends BasePostgresRepository {
  PostgresShadowExecutionRepository(super.client);

  Future<List<ShadowExecution>> findUnlinked({
    required String organizationId,
    int limit = 50,
  }) async {
    try {
      final rows = await client
          .from('shadow_executions')
          .select()
          .eq('organization_id', organizationId)
          .eq('status', 'UNLINKED_SHADOW')
          .order('created_at_utc', ascending: false)
          .limit(limit);
      return (rows as List<dynamic>)
          .map((r) => _fromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_execution');
    }
  }

  Future<ShadowExecution?> findById({
    required String id,
    required String organizationId,
  }) async {
    try {
      final row = await client
          .from('shadow_executions')
          .select()
          .eq('id', id)
          .eq('organization_id', organizationId) // INV-1
          .maybeSingle();
      if (row == null) return null; // INV-26: same shape as wrong-org
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_execution');
    }
  }

  Future<void> reconcile({
    required String id,
    required String organizationId,
    required String reconciledExecutionId,
    required String reconciledByUserId,
    required DateTime atUtc,
  }) async {
    try {
      await client
          .from('shadow_executions')
          .update({
            'status': ShadowExecutionStatus.reconciled.dbValue,
            'reconciled_execution_id': reconciledExecutionId,
            'reconciled_at_utc': atUtc.toUtc().toIso8601String(), // INV-6
            'reconciled_by_user_id': reconciledByUserId,
          })
          .eq('id', id)
          .eq('organization_id', organizationId); // INV-1
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_execution');
    }
  }

  Future<void> dismiss({
    required String id,
    required String organizationId,
    required String dismissedByUserId,
    required String reason,
    required DateTime atUtc,
  }) async {
    try {
      await client
          .from('shadow_executions')
          .update({
            'status': ShadowExecutionStatus.dismissed.dbValue,
            'dismissed_at_utc': atUtc.toUtc().toIso8601String(), // INV-6
            'dismissed_by_user_id': dismissedByUserId,
            'dismissed_reason': reason,
          })
          .eq('id', id)
          .eq('organization_id', organizationId); // INV-1
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_execution');
    }
  }

  /// Promotes a shadow to a new ad-hoc billable execution (RECONCILED_AS_NEW_REVENUE).
  /// Transition audit log is auto-inserted by DB trigger (INV-3/INV-21).
  Future<void> reconcileAsNewRevenue({
    required String id,
    required String organizationId,
    required String reconciledExecutionId,
    required String reconciledByUserId,
    required DateTime atUtc,
  }) async {
    try {
      await client
          .from('shadow_executions')
          .update({
            'status': ShadowExecutionStatus.reconciledAsNewRevenue.dbValue,
            'reconciled_execution_id': reconciledExecutionId,
            'reconciled_at_utc': atUtc.toUtc().toIso8601String(), // INV-6
            'reconciled_by_user_id': reconciledByUserId,
          })
          .eq('id', id)
          .eq('organization_id', organizationId); // INV-1
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_execution');
    }
  }

  static ShadowExecution _fromRow(Map<String, dynamic> row) {
    return ShadowExecution(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      operatorId: row['operator_id'] as String,
      chatId: row['chat_id'] as int,
      telegramMessageId: row['telegram_message_id'] as int,
      originEvidenceId: row['origin_evidence_id'] as String,
      originChannel: row['origin_channel'] as String? ?? 'telegram',
      messageTs: row['message_ts'] as int,
      countedFromUtc: DateTime.parse(row['counted_from_utc'] as String),
      status: ShadowExecutionStatusX.fromDb(row['status'] as String),
      reconciledExecutionId: row['reconciled_execution_id'] as String?,
      reconciledAtUtc: row['reconciled_at_utc'] != null
          ? DateTime.parse(row['reconciled_at_utc'] as String)
          : null,
      reconciledByUserId: row['reconciled_by_user_id'] as String?,
      dismissedAtUtc: row['dismissed_at_utc'] != null
          ? DateTime.parse(row['dismissed_at_utc'] as String)
          : null,
      dismissedByUserId: row['dismissed_by_user_id'] as String?,
      dismissedReason: row['dismissed_reason'] as String?,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String),
    );
  }
}
