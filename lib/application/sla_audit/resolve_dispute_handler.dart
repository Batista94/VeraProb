import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_dispute_resolution_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_transition_guard.dart';
import 'resolve_dispute_command.dart';

/// Application handler for [ResolveDisputeCommand].
///
/// Closes the `disputed` dead-end: an auditor resolves a disputed sanction into
/// one of three arcs (accept/overturn/retract). All arcs are validated by the
/// centralized [SanctionTransitionGuard] before the write.
///
/// **Concurrency + atomicity (DB-enforced):** the write path is a single call to
/// [SanctionDisputeResolutionRepository.resolveDispute], backed by the
/// `resolve_dispute` SECURITY DEFINER RPC. The RPC row-locks the queue entry,
/// re-checks the `disputed` status (closing the TOCTOU race), appends the
/// resolution ledger fact (INV-3), flips the queue, and seals the overturn
/// snapshot (INV-21) — all in ONE transaction. The former 3–4 non-atomic
/// PostgREST round-trips are gone. A concurrent loser raises
/// [IdempotencyProcessingException] from the RPC; no second fact is appended.
///
/// The client-side checks below (tenant, RBAC, reason, status, transition) are
/// retained as fail-fast UX and anti-oracle guards; they are NOT the concurrency
/// barrier — that is the DB row lock.
class ResolveDisputeHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionDisputeResolutionRepository _resolutionRepo;
  final RbacService _rbac;
  final IDateTimeProvider _clock;
  final SanctionTransitionGuard _guard;

  ResolveDisputeHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionDisputeResolutionRepository resolutionRepo,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _resolutionRepo = resolutionRepo,
       _rbac = rbac,
       _clock = dateTimeProvider ?? BrazilDateTimeProvider(),
       _guard = const SanctionTransitionGuard();

  Future<void> handle(ResolveDisputeCommand command) async {
    // 1. Fail-Fast tenant sync (INV-1, INV-22).
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC — same authority as reject. Before any I/O (anti-oracle).
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Structured reason_code mandatory for accept/overturn (Q2); free text
    // optional. Authoritative catalogue validation is server-side (H5).
    _assertReasonCode(command);

    // 4. Load entry scoped to organizationId (tenant isolation, INV-1).
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 5. Handler ownership: this handler resolves ONLY disputed entries. The
    // `disputed → *` arcs belong exclusively here; pending entries are owned by
    // approve/reject/dispute.
    if (entry.status != SanctionReviewStatus.disputed) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is not disputed '
        '(status: ${entry.status.name}).',
      );
    }

    // 6. State-machine legality (centralized).
    final target = _targetStatus(command.resolution);
    _guard.assertTransitionAllowed(entry.status, target);

    // 7. Atomic write (lock → re-check → ledger append → queue flip → overturn
    // seal) in ONE DB transaction. Concurrency control + atomicity live here.
    final ledgerType = _ledgerType(command.resolution);
    await _resolutionRepo.resolveDispute(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      resolution: ledgerType,
      resolutionReason: command.resolutionReason?.trim(),
      reasonCode: command.reasonCode,
      resolvedByUserId: command.resolvedByUserId,
      actorEmail: command.actorEmail,
      occurredAtUtc: _clock.nowUtc(),
      idempotencyKey: '${command.queueEntryId}:$ledgerType:SNAPSHOT',
    );
  }

  void _assertReasonCode(ResolveDisputeCommand command) {
    if (command.resolution == DisputeResolution.retract) return;
    final code = command.reasonCode?.trim();
    if (code == null || code.isEmpty) {
      throw const DomainException(
        'A reason code is required for this resolution.',
      );
    }
    // OTHER requires a free-text complement (UX forcing-function parity).
    if (code == 'OTHER' &&
        (command.resolutionReason?.trim().length ?? 0) < 10) {
      throw const DomainException(
        'OTHER requires a description (>= 10 chars).',
      );
    }
  }

  SanctionReviewStatus _targetStatus(DisputeResolution resolution) {
    switch (resolution) {
      case DisputeResolution.accept:
        return SanctionReviewStatus.rejected;
      case DisputeResolution.overturn:
        return SanctionReviewStatus.applied;
      case DisputeResolution.retract:
        return SanctionReviewStatus.pending;
    }
  }

  String _ledgerType(DisputeResolution resolution) {
    switch (resolution) {
      case DisputeResolution.accept:
        return 'DISPUTE_ACCEPTED';
      case DisputeResolution.overturn:
        return 'DISPUTE_OVERTURNED';
      case DisputeResolution.retract:
        return 'DISPUTE_RETRACTED';
    }
  }
}
