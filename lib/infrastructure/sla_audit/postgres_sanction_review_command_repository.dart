// pr_scanner: ignore-regression
// Council-reviewed (Phase 10.6 v3 council-remediated plan, 2026-06-12):
// dispute reality core — evidence/reason-code/command contracts (INV-1/3/9).
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/concurrent_modification_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_sanction_result.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';
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
    String? reasonCode,
    String? reviewerReason,
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
          'p_reason_code': reasonCode,
          'p_reviewer_reason': reviewerReason,
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
    required String reasonCode,
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
          'p_reason_code': reasonCode,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
        },
      );
      return SanctionReviewResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'reject_sanction');
    }
  }

  @override
  Future<SanctionReviewResult> confirmPeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'confirm_peer_review',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_reviewed_by_user_id': reviewedByUserId,
          'p_actor_email': actorEmail,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
          'p_idempotency_key': queueEntryId,
        },
      );
      return SanctionReviewResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'confirm_peer_review');
    }
  }

  @override
  Future<SanctionReviewResult> declinePeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String reason,
    required DateTime occurredAtUtc,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'decline_peer_review',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_reviewed_by_user_id': reviewedByUserId,
          'p_actor_email': actorEmail,
          'p_reason': reason,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
        },
      );
      return SanctionReviewResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'decline_peer_review');
    }
  }

  @override
  Future<DisputeSanctionResult> disputeSanction({
    required String organizationId,
    required String queueEntryId,
    required String disputedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    try {
      final result = await client.rpc<Map<String, dynamic>>(
        'dispute_sanction',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_disputed_by_user_id': disputedByUserId,
          'p_actor_email': actorEmail,
          'p_occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
        },
      );
      return DisputeSanctionResult.fromJson(result);
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'dispute_sanction');
    }
  }

  @override
  Future<String> generateDisputePortalToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
  }) async {
    try {
      final token = await client.rpc<String>(
        'generate_dispute_portal_token',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_created_by': createdByUserId,
        },
      );
      return token;
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'generate_dispute_portal_token');
    }
  }

  @override
  Future<String> generatePortalSubmitToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
  }) async {
    try {
      final token = await client.rpc<String>(
        'generate_portal_submit_token',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_created_by': createdByUserId,
        },
      );
      return token;
    } on PostgrestException catch (e) {
      throw _mapError(e, queueEntryId, 'generate_portal_submit_token');
    }
  }

  Object _mapError(
    PostgrestException e,
    String queueEntryId,
    String commandPath,
  ) {
    final detail = e.details?.toString() ?? '';
    // Distinct governance guard: surface a clear message (caller is a valid
    // auditor of the right tenant; this is NOT an anti-oracle rejection).
    if (e.code == '55P03') {
      return const ConcurrentModificationException();
    }
    if (e.code == 'P0001' &&
        detail.contains('DualControlSelfApprovalException')) {
      return DualControlSelfApprovalException(
        queueEntryId: queueEntryId,
        message: e.message,
      );
    }
    if (e.code == 'P0001' &&
        detail.contains('IdempotencyProcessingException')) {
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
