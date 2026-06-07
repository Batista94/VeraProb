import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_event.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_transition_guard.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'resolve_dispute_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [ResolveDisputeCommand].
///
/// Closes the `disputed` dead-end: an auditor resolves a disputed sanction into
/// one of three arcs (accept/overturn/retract). All arcs are validated by the
/// centralized [SanctionTransitionGuard] and anchored by a distinct ledger fact
/// for deterministic replay (INV-15).
///
/// **Concurrency:** a non-RPC idempotency guard balances `SANCTION_DISPUTED`
/// opens against resolution facts in the ledger. If the current dispute was
/// already resolved by another auditor, it raises
/// [IdempotencyProcessingException] before any side-effect (no double append).
class ResolveDisputeHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SlaAuditLedgerRepository _ledger;
  final ForensicEvidenceSnapshotRepository _vault;
  final RbacService _rbac;
  final IDateTimeProvider _clock;
  final SanctionTransitionGuard _guard;

  ResolveDisputeHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    required ForensicEvidenceSnapshotRepository vault,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _ledger = ledger,
       _vault = vault,
       _rbac = rbac,
       _clock = dateTimeProvider ?? BrazilDateTimeProvider(),
       _guard = const SanctionTransitionGuard();

  static const _resolutionTypes = {
    'DISPUTE_ACCEPTED',
    'DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED',
  };

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

    // 3. Reason is mandatory for accept/overturn (forensic traceability).
    _assertReason(command);

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

    // 7. Idempotency guard (concurrency): the current dispute must be unresolved.
    await _assertCurrentDisputeUnresolved(command, entry.organizationId);

    final now = _clock.nowUtc();
    final reason = command.resolutionReason?.trim();

    // 8. Append the resolution fact FIRST (INV-3 append-only, Pillar C).
    final event = _buildEvent(command, entry, now, reason);
    final ledgerEntryId = await _ledger.append(
      SlaLedgerMapper.mapToEntry(event),
    );

    // 9. Apply the queue transition.
    await _queueRepo.updateStatus(
      _applyTransition(entry, command, now, reason),
    );

    // 10. Seal forensic snapshot for overturn arc (INV-9, INV-21).
    //     Linked to the DISPUTE_OVERTURNED ledger entry just appended.
    //     No new ledger entry is created (INV-3).
    if (command.resolution == DisputeResolution.overturn) {
      await _vault.sealForDispute(
        organizationId: command.organizationId,
        ledgerEntryId: ledgerEntryId,
        contractId: entry.contractId,
        setId: entry.setId,
        planVersion: 0,
        occurredAtUtc: now,
        sealedBy: command.resolvedByUserId,
        idempotencyKey: '${command.queueEntryId}:DISPUTE_OVERTURNED:SNAPSHOT',
      );
    }
  }

  void _assertReason(ResolveDisputeCommand command) {
    if (command.resolution == DisputeResolution.retract) return;
    if ((command.resolutionReason?.trim().length ?? 0) < 10) {
      throw const DomainException(
        'resolutionReason must be at least 10 characters.',
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

  Future<void> _assertCurrentDisputeUnresolved(
    ResolveDisputeCommand command,
    String organizationId,
  ) async {
    final related = await _ledger.getEntriesByQueueEntryId(
      command.queueEntryId,
      organizationId: organizationId,
    );
    final opens = related.where((e) => e.type == 'SANCTION_DISPUTED').length;
    final resolutions = related
        .where((e) => _resolutionTypes.contains(e.type))
        .length;
    if (resolutions >= opens) {
      throw IdempotencyProcessingException(
        idempotencyKey: command.queueEntryId,
        commandPath: 'resolve_dispute',
        message: 'This dispute has already been resolved by another auditor.',
      );
    }
  }

  DomainEvent _buildEvent(
    ResolveDisputeCommand command,
    SanctionReviewQueueEntry entry,
    DateTime now,
    String? reason,
  ) {
    final args = (
      organizationId: entry.organizationId,
      occurredAtUtc: now,
      setId: entry.setId,
      contractId: entry.contractId,
      queueEntryId: entry.id,
      resolvedByUserId: command.resolvedByUserId,
      actorEmail: command.actorEmail,
      resolutionReason: reason,
      verdictEvidence: entry.verdictEvidence,
    );
    switch (command.resolution) {
      case DisputeResolution.accept:
        return DisputeAcceptedEvent(
          organizationId: args.organizationId,
          occurredAtUtc: args.occurredAtUtc,
          setId: args.setId,
          contractId: args.contractId,
          planVersion: 0,
          queueEntryId: args.queueEntryId,
          resolvedByUserId: args.resolvedByUserId,
          actorEmail: args.actorEmail,
          resolutionReason: args.resolutionReason,
          verdictEvidence: args.verdictEvidence,
        );
      case DisputeResolution.overturn:
        return DisputeOverturnedEvent(
          organizationId: args.organizationId,
          occurredAtUtc: args.occurredAtUtc,
          setId: args.setId,
          contractId: args.contractId,
          planVersion: 0,
          queueEntryId: args.queueEntryId,
          resolvedByUserId: args.resolvedByUserId,
          actorEmail: args.actorEmail,
          resolutionReason: args.resolutionReason,
          verdictEvidence: args.verdictEvidence,
        );
      case DisputeResolution.retract:
        return DisputeRetractedEvent(
          organizationId: args.organizationId,
          occurredAtUtc: args.occurredAtUtc,
          setId: args.setId,
          contractId: args.contractId,
          planVersion: 0,
          queueEntryId: args.queueEntryId,
          resolvedByUserId: args.resolvedByUserId,
          actorEmail: args.actorEmail,
          resolutionReason: args.resolutionReason,
          verdictEvidence: args.verdictEvidence,
        );
    }
  }

  SanctionReviewQueueEntry _applyTransition(
    SanctionReviewQueueEntry entry,
    ResolveDisputeCommand command,
    DateTime now,
    String? reason,
  ) {
    switch (command.resolution) {
      case DisputeResolution.accept:
        return entry.copyWith(
          status: SanctionReviewStatus.rejected,
          reviewedAtUtc: now,
          reviewedByUserId: command.resolvedByUserId,
          rejectionReason: reason,
        );
      case DisputeResolution.overturn:
        return entry.copyWith(
          status: SanctionReviewStatus.applied,
          reviewedAtUtc: now,
          reviewedByUserId: command.resolvedByUserId,
        );
      case DisputeResolution.retract:
        // Return to the queue: wipe the review trail but preserve the original
        // disputer (reviewedByUserId) for forensic honesty.
        return entry.copyWith(
          status: SanctionReviewStatus.pending,
          clearReviewedAtUtc: true,
          clearRejectionReason: true,
        );
    }
  }
}
