import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_sanction_result.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// In-memory implementation of [SanctionReviewCommandRepository].
///
/// Mirrors the `approve_sanction` / `reject_sanction` / `dispute_sanction` SECURITY DEFINER RPCs
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
    int? dualControlThresholdCents,
    int dualControlTtlHours = 48,
  }) : _queue = queueRepo,
       _ledger = ledger,
       _thresholdCents = dualControlThresholdCents,
       _ttlHours = dualControlTtlHours;

  final SanctionReviewQueueRepository _queue;
  final SlaAuditLedgerRepository _ledger;

  /// Dual-control threshold (BIGINT cents). `null` ⇒ dual-control OFF (every
  /// verdict goes terminal). Mirrors `COALESCE(contract, org)` resolved by the
  /// DB; in-memory mode takes a single flat value.
  final int? _thresholdCents;
  final int _ttlHours;

  static const _verdictTypes = {
    'VERDICT_SEALED',
    'VERDICT_REFUSED',
    'SANCTION_DISPUTED',
  };

  @override
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    final entry = await _lockPending(organizationId, queueEntryId);

    if (_exceedsThreshold(entry)) {
      return _forkToPeerReview(
        entry: entry,
        reviewedByUserId: reviewedByUserId,
        actorEmail: actorEmail,
        proposedAction: 'APPROVE',
        originStatus: 'pending',
        reason: null,
        occurredAtUtc: occurredAtUtc,
      );
    }

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
  Future<DisputeSanctionResult> disputeSanction({
    required String organizationId,
    required String queueEntryId,
    required String disputedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    final entry = await _lockPending(organizationId, queueEntryId);

    // SLA logic mocked for in-memory (e.g. + 5 days)
    final resolutionDue = occurredAtUtc.add(const Duration(days: 5));

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'SANCTION_DISPUTED',
        operatorId: disputedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'disputed_by_user_id': disputedByUserId,
          'actor_email': actorEmail,
          'verdict_evidence': entry.verdictEvidence.toJson(),
          'resolution_due_at': resolutionDue.toIso8601String(),
          'dispute_sla_days': 5,
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(
        status: SanctionReviewStatus.disputed,
        reviewedAtUtc: occurredAtUtc,
        reviewedByUserId: disputedByUserId,
      ),
    );

    return DisputeSanctionResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: 'disputed',
      resolutionDueAtUtc: resolutionDue,
    );
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
    final reason = rejectionReason.trim();
    if (reason.isEmpty || reasonCode.trim().isEmpty) {
      // Mirrors the RPC's fail-closed empty-reason / empty-code guard
      // (opaque, INV-26).
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Sanction rejection rejected.',
      );
    }

    final entry = await _lockPending(organizationId, queueEntryId);

    if (_exceedsThreshold(entry)) {
      return _forkToPeerReview(
        entry: entry,
        reviewedByUserId: reviewedByUserId,
        actorEmail: actorEmail,
        proposedAction: 'REJECT',
        originStatus: 'pending',
        reason: reason,
        occurredAtUtc: occurredAtUtc,
      );
    }

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
          'reason_code': reasonCode.trim(),
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

  @override
  Future<SanctionReviewResult> confirmPeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async {
    final entry = await _lockPeerReview(organizationId, queueEntryId);

    // ★ ANTI-FRAUD: reviewer2 must differ from reviewer1.
    if (reviewedByUserId == entry.firstReviewerId) {
      throw DualControlSelfApprovalException(queueEntryId: queueEntryId);
    }

    final (status, ledgerType) = switch (entry.peerReviewProposedAction) {
      'APPROVE' => (SanctionReviewStatus.applied, 'VERDICT_SEALED'),
      'OVERTURN' => (SanctionReviewStatus.applied, 'DISPUTE_OVERTURNED'),
      'REJECT' => (SanctionReviewStatus.rejected, 'VERDICT_REFUSED'),
      'DISPUTE_ACCEPT' => (SanctionReviewStatus.rejected, 'DISPUTE_ACCEPTED'),
      _ => throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Peer review rejected.',
      ),
    };

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: ledgerType,
        operatorId: reviewedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'first_reviewer_id': entry.firstReviewerId,
          'second_reviewer_id': reviewedByUserId,
          'confirmed_by_user_id': reviewedByUserId,
          'actor_email': actorEmail,
          'proposed_action': entry.peerReviewProposedAction,
          'verdict_evidence': entry.verdictEvidence.toJson(),
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(
        status: status,
        reviewedAtUtc: occurredAtUtc,
        reviewedByUserId: reviewedByUserId,
        clearPeerReview: true,
      ),
    );

    return SanctionReviewResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: status.dbValue,
    );
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
    final entry = await _lockPeerReview(organizationId, queueEntryId);
    final origin = entry.peerReviewOriginStatus == 'disputed'
        ? SanctionReviewStatus.disputed
        : SanctionReviewStatus.pending;

    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'PEER_REVIEW_DECLINED',
        operatorId: reviewedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'declined_by_user_id': reviewedByUserId,
          'first_reviewer_id': entry.firstReviewerId,
          'actor_email': actorEmail,
          'origin_status': origin.dbValue,
          'decline_reason': reason.trim().isEmpty ? null : reason.trim(),
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(status: origin, clearPeerReview: true),
    );

    return SanctionReviewResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: origin.dbValue,
    );
  }

  @override
  Future<String> generateDisputePortalToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
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
        message: 'Dispute portal token rejected.',
      );
    }
    if (entry.status != SanctionReviewStatus.disputed &&
        entry.status != SanctionReviewStatus.applied) {
      throw IdempotencyProcessingException(
        idempotencyKey: queueEntryId,
        commandPath: 'generate_dispute_portal_token',
        message: 'A portal link can only be issued for a contested sanction.',
      );
    }

    final token = _nextPortalToken();
    await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'DISPUTE_PORTAL_TOKEN_GENERATED',
        operatorId: createdByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: DateTime.now().toUtc(),
        payload: {
          'queue_entry_id': queueEntryId,
          'created_by_user_id': createdByUserId,
          'token': token,
        },
      ),
    );
    return token;
  }

  int _portalTokenSeq = 0;

  /// Deterministic UUID-shaped token for in-memory mode (tests). Monotonic so
  /// repeated generations never collide, mirroring the DB's UNIQUE token.
  String _nextPortalToken() {
    final seq = (++_portalTokenSeq).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$seq';
  }

  bool _exceedsThreshold(SanctionReviewQueueEntry entry) {
    final threshold = _thresholdCents;
    return threshold != null &&
        entry.verdictEvidence.fineCents.cents > threshold;
  }

  Future<SanctionReviewResult> _forkToPeerReview({
    required SanctionReviewQueueEntry entry,
    required String reviewedByUserId,
    required String actorEmail,
    required String proposedAction,
    required String originStatus,
    required String? reason,
    required DateTime occurredAtUtc,
  }) async {
    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: entry.organizationId,
        type: 'PEER_REVIEW_REQUESTED',
        operatorId: reviewedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': entry.id,
          'first_reviewer_id': reviewedByUserId,
          'actor_email': actorEmail,
          'proposed_action': proposedAction,
          'peer_review_reason': reason,
          'fine_cents': entry.verdictEvidence.fineCents.cents,
          'threshold_cents': _thresholdCents,
          'verdict_evidence': entry.verdictEvidence.toJson(),
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(
        status: SanctionReviewStatus.pendingPeerReview,
        firstReviewerId: reviewedByUserId,
        peerReviewProposedAction: proposedAction,
        peerReviewOriginStatus: originStatus,
        peerReviewExpiresAtUtc: occurredAtUtc.add(Duration(hours: _ttlHours)),
      ),
    );

    return SanctionReviewResult(
      ledgerEntryId: ledgerEntryId,
      finalQueueStatus: 'pending_peer_review',
    );
  }

  /// Re-reads an entry expected to be in `pending_peer_review`, mirroring the
  /// RPC's anti-oracle + idempotency posture.
  Future<SanctionReviewQueueEntry> _lockPeerReview(
    String organizationId,
    String queueEntryId,
  ) async {
    final entry = await _queue.findById(
      queueEntryId,
      organizationId: organizationId,
    );
    if (entry == null) {
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Peer review rejected.',
      );
    }
    if (entry.status != SanctionReviewStatus.pendingPeerReview) {
      throw IdempotencyProcessingException(
        idempotencyKey: queueEntryId,
        commandPath: 'peer_review',
        message: 'This item is no longer awaiting a second auditor.',
      );
    }
    return entry;
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
