import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';
import 'package:veraprob/domain/sla_audit/sanction_dispute_resolution_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [SanctionDisputeResolutionRepository].
///
/// Single write path: the `resolve_dispute` SECURITY DEFINER RPC. No direct
/// table mutation exists here — atomicity and concurrency control live in the
/// database transaction (row lock + status re-check).
///
/// **Error mapping:**
/// - `P0001` + DETAIL `IdempotencyProcessingException` → the concurrent loser
///   lost the row-lock race / the dispute was already resolved →
///   [IdempotencyProcessingException] (not an error — a concurrency guard).
/// - Everything else (e.g. `42501` cross-tenant / wrong-role / NULL-JWT) →
///   [mapPostgrestToDomainException] → opaque 404 via the shared interceptor
///   (INV-26 anti-oracle). No raw DB code leaks to the caller.
class PostgresSanctionDisputeResolutionRepository extends BasePostgresRepository
    implements SanctionDisputeResolutionRepository {
  PostgresSanctionDisputeResolutionRepository(super.client);

  @override
  Future<DisputeResolutionResult> resolveDispute({
    required String organizationId,
    required String queueEntryId,
    required String resolution,
    required String? resolutionReason,
    required String? reasonCode,
    required String resolvedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    required String idempotencyKey,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'resolve_dispute',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_resolution': resolution,
          'p_resolution_reason': resolutionReason,
          'p_resolved_by_user_id': resolvedByUserId,
          'p_actor_email': actorEmail,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
          'p_idempotency_key': idempotencyKey,
          'p_reason_code': reasonCode,
        },
      );
      return DisputeResolutionResult.fromJson(result);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001' &&
          (e.details?.toString().contains('IdempotencyProcessingException') ??
              false)) {
        throw IdempotencyProcessingException(
          idempotencyKey: idempotencyKey,
          commandPath: 'resolve_dispute',
          message: e.message,
        );
      }
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'dispute_resolution',
        resourceId: queueEntryId,
      );
    }
  }
}
