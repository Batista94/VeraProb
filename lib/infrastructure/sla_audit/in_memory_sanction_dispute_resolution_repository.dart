import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_dispute_resolution_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// In-memory implementation of [SanctionDisputeResolutionRepository].
///
/// Mirrors the `resolve_dispute` SECURITY DEFINER RPC against the in-memory
/// queue + ledger + vault so in-memory persistence mode (and handler unit
/// tests) exercise the SAME atomic semantics as Postgres:
///   look up (locked) → status re-check → ledger append → queue flip →
///   (overturn) inline snapshot seal.
///
/// Concurrency guards reproduced here as fail-fast checks:
/// - entry missing / wrong org → [SovereigntyViolationException] (mirrors the
///   RPC's 42501 anti-oracle posture, INV-26);
/// - entry no longer `disputed` OR a resolution fact already exists for the
///   queue entry (the per-partition unique-index backstop) →
///   [IdempotencyProcessingException] (mirrors the RPC's concurrent-loser path,
///   no second ledger fact is appended).
class InMemorySanctionDisputeResolutionRepository
    implements SanctionDisputeResolutionRepository {
  InMemorySanctionDisputeResolutionRepository({
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    required ForensicEvidenceSnapshotRepository vault,
  }) : _queue = queueRepo,
       _ledger = ledger,
       _vault = vault;

  final SanctionReviewQueueRepository _queue;
  final SlaAuditLedgerRepository _ledger;
  final ForensicEvidenceSnapshotRepository _vault;

  static const _resolutionTypes = {
    'DISPUTE_ACCEPTED',
    'DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED',
  };

  @override
  Future<DisputeResolutionResult> resolveDispute({
    required String organizationId,
    required String queueEntryId,
    required String resolution,
    required String? resolutionReason,
    required String resolvedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    required String idempotencyKey,
  }) async {
    final entry = await _queue.findById(
      queueEntryId,
      organizationId: organizationId,
    );
    if (entry == null) {
      // Anti-oracle (INV-26): not-found and wrong-org are indistinguishable.
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Dispute resolution rejected.',
      );
    }

    if (entry.status != SanctionReviewStatus.disputed) {
      throw IdempotencyProcessingException(
        idempotencyKey: idempotencyKey,
        commandPath: 'resolve_dispute',
        message: 'This dispute has already been resolved by another auditor.',
      );
    }

    // Unique-index backstop: a resolution fact already exists for this entry.
    final related = await _ledger.getEntriesByQueueEntryId(
      queueEntryId,
      organizationId: organizationId,
    );
    if (related.any((e) => _resolutionTypes.contains(e.type))) {
      throw IdempotencyProcessingException(
        idempotencyKey: idempotencyKey,
        commandPath: 'resolve_dispute',
        message: 'This dispute has already been resolved by another auditor.',
      );
    }

    final reason = resolutionReason?.trim();
    final cleanReason = (reason == null || reason.isEmpty) ? null : reason;

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: resolution,
        operatorId: resolvedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'resolved_by_user_id': resolvedByUserId,
          'actor_email': actorEmail,
          'resolution_reason': cleanReason,
          'verdict_evidence': entry.verdictEvidence.toJson(),
        },
      ),
    );

    await _queue.updateStatus(
      _applyTransition(
        entry,
        resolution,
        resolvedByUserId,
        occurredAtUtc,
        cleanReason,
      ),
    );

    Map<String, dynamic>? snapshot;
    if (resolution == 'DISPUTE_OVERTURNED') {
      final sealed = await _vault.sealForDispute(
        organizationId: organizationId,
        ledgerEntryId: ledgerEntryId,
        contractId: entry.contractId,
        setId: entry.setId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        sealedBy: resolvedByUserId,
        idempotencyKey: idempotencyKey,
      );
      snapshot = Map<String, dynamic>.from(sealed.snapshot);
    }

    return DisputeResolutionResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: _statusFor(resolution),
      snapshot: snapshot,
    );
  }

  String _statusFor(String resolution) {
    switch (resolution) {
      case 'DISPUTE_ACCEPTED':
        return 'rejected';
      case 'DISPUTE_OVERTURNED':
        return 'applied';
      default:
        return 'pending';
    }
  }

  SanctionReviewQueueEntry _applyTransition(
    SanctionReviewQueueEntry entry,
    String resolution,
    String resolvedByUserId,
    DateTime occurredAtUtc,
    String? reason,
  ) {
    switch (resolution) {
      case 'DISPUTE_ACCEPTED':
        return entry.copyWith(
          status: SanctionReviewStatus.rejected,
          reviewedAtUtc: occurredAtUtc,
          reviewedByUserId: resolvedByUserId,
          rejectionReason: reason,
        );
      case 'DISPUTE_OVERTURNED':
        return entry.copyWith(
          status: SanctionReviewStatus.applied,
          reviewedAtUtc: occurredAtUtc,
          reviewedByUserId: resolvedByUserId,
        );
      default:
        return entry.copyWith(
          status: SanctionReviewStatus.pending,
          clearReviewedAtUtc: true,
          clearRejectionReason: true,
        );
    }
  }
}
