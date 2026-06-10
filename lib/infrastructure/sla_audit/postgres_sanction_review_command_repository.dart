import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [SanctionReviewCommandRepository].
///
/// Single write path per verdict: the `approve_sanction` / `reject_sanction`
/// SECURITY DEFINER RPCs. No direct table mutation exists here — atomicity and
/// concurrency control live in the database transaction (row lock + status
/// re-check).
///
/// **Error mapping:**
/// - `P0001` + DETAIL `IdempotencyProcessingException` → the concurrent loser
///   lost the row-lock race / the sanction was already reviewed →
///   [IdempotencyProcessingException] (not an error — a concurrency guard).
/// - Everything else (e.g. `42501` cross-tenant / wrong-role / NULL-JWT /
///   reviewer-mismatch) → [mapPostgrestToDomainException] → opaque 404 via the
///   shared interceptor (INV-26 anti-oracle). No raw DB code leaks to the caller.
class PostgresSanctionReviewCommandRepository extends BasePostgresRepository
    implements SanctionReviewCommandRepository {
  PostgresSanctionReviewCommandRepository(super.client);

  @override
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'approve_sanction',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_reviewed_by_user_id': reviewedByUserId,
          'p_actor_email': actorEmail,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
        },
      );
      return SanctionReviewResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'approve_sanction');
    }
  }

  @override
  Future<SanctionReviewResult> rejectSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required DateTime occurredAtUtc,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'reject_sanction',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_reviewed_by_user_id': reviewedByUserId,
          'p_actor_email': actorEmail,
          'p_rejection_reason': rejectionReason,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
        },
      );
      return SanctionReviewResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'reject_sanction');
    }
  }

  Object _mapError(
    PostgrestException e,
    String queueEntryId,
    String commandPath,
  ) {
    if (e.code == 'P0001' &&
        (e.details?.toString().contains('IdempotencyProcessingException') ??
            false)) {
      return IdempotencyProcessingException(
        idempotencyKey: queueEntryId,
        commandPath: commandPath,
        message: e.message,
      );
    }
    return mapPostgrestToDomainException(
      e,
      resourceType: 'sanction_review',
      resourceId: queueEntryId,
    );
  }
}
