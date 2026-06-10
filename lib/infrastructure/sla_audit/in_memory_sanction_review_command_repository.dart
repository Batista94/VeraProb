import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// In-memory implementation of [SanctionReviewCommandRepository].
///
/// Mirrors the `approve_sanction` / `reject_sanction` SECURITY DEFINER RPCs
/// against the in-memory queue + ledger so in-memory persistence mode (and
/// handler unit tests) exercise the SAME atomic semantics as Postgres:
///   look up (locked) → status re-check → ledger append → queue flip.
///
/// Concurrency guards reproduced here as fail-fast checks:
/// - entry missing / wrong org → [SovereigntyViolationException] (mirrors the
///   RPC's 42501 anti-oracle posture, INV-26);
/// - entry no longer `pending` OR a verdict fact already exists for the queue
///   entry → [IdempotencyProcessingException] (mirrors the RPC's concurrent-loser
///   path; no second ledger fact is appended).
class InMemorySanctionReviewCommandRepository
    implements SanctionReviewCommandRepository {
  InMemorySanctionReviewCommandRepository({
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
  }) : _queue = queueRepo,
       _ledger = ledger;

  final SanctionReviewQueueRepository _queue;
  final SlaAuditLedgerRepository _ledger;

  static const _verdictTypes = {'VERDICT_SEALED', 'VERDICT_REFUSED'};

  @override
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    final entry = await _lockPending(organizationId, queueEntryId);

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'VERDICT_SEALED',
        operatorId: reviewedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'approved_by_user_id': reviewedByUserId,
          'actor_email': actorEmail,
          'verdict_evidence': entry.verdictEvidence.toJson(),
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(
        status: SanctionReviewStatus.applied,
        reviewedAtUtc: occurredAtUtc,
        reviewedByUserId: reviewedByUserId,
      ),
    );

    return SanctionReviewResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: 'applied',
    );
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
    final reason = rejectionReason.trim();
    if (reason.isEmpty) {
      // Mirrors the RPC's fail-closed empty-reason guard (opaque, INV-26).
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Sanction rejection rejected.',
      );
    }

    final entry = await _lockPending(organizationId, queueEntryId);

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'VERDICT_REFUSED',
        operatorId: reviewedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'rejected_by_user_id': reviewedByUserId,
          'actor_email': actorEmail,
          'rejection_reason': reason,
          'verdict_evidence': entry.verdictEvidence.toJson(),
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(
        status: SanctionReviewStatus.rejected,
        reviewedAtUtc: occurredAtUtc,
        reviewedByUserId: reviewedByUserId,
        rejectionReason: reason,
      ),
    );

    return SanctionReviewResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: 'rejected',
    );
  }

  /// Re-reads the entry under the same anti-oracle + idempotency posture as the
  /// RPC, returning it only when it is genuinely `pending`.
  Future<SanctionReviewQueueEntry> _lockPending(
    String organizationId,
    String queueEntryId,
  ) async {
    final entry = await _queue.findById(
      queueEntryId,
      organizationId: organizationId,
    );
    if (entry == null) {
      // Anti-oracle (INV-26): not-found and wrong-org are indistinguishable.
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Sanction review rejected.',
      );
    }

    if (entry.status != SanctionReviewStatus.pending) {
      throw IdempotencyProcessingException(
        idempotencyKey: queueEntryId,
        commandPath: 'sanction_review',
        message: 'This sanction has already been reviewed by another auditor.',
      );
    }

    // Backstop: a verdict fact already exists for this entry.
    final related = await _ledger.getEntriesByQueueEntryId(
      queueEntryId,
      organizationId: organizationId,
    );
    if (related.any((e) => _verdictTypes.contains(e.type))) {
      throw IdempotencyProcessingException(
        idempotencyKey: queueEntryId,
        commandPath: 'sanction_review',
        message: 'This sanction has already been reviewed by another auditor.',
      );
    }

    return entry;
  }
}
