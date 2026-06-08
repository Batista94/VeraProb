import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'dispute_sanction_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [DisputeSanctionCommand].
///
/// Under the CIA Triad:
/// 1. **Confidentiality:** Scopes queue retrieval to [command.organizationId] and asserts tenant identity.
/// 2. **Integrity:** Enforces RBAC roles and prevents changing states of already finalized entries.
/// 3. **Availability:** Ensures predictable execution transitions.
class DisputeSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  DisputeSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _ledger = ledger,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  /// Transitions a pending queue entry to `disputed` (Hold / Waiting for Evidence).
  /// Appends a `SANCTION_DISPUTED` entry to the immutable ledger for audit traceability.
  Future<void> handle(DisputeSanctionCommand command) async {
    // 1. Fail-Fast Tenant Sync (INV-1, INV-22)
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check (same authorization required as reject)
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load entry scoped to organizationId (tenant isolation, INV-6)
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 4. Idempotency guard (INV-24): only pending entries can transition
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    final now = _dateTimeProvider.nowUtc();

    // 5. Build domain event
    final event = SanctionDisputedEvent(
      organizationId: entry.organizationId,
      occurredAtUtc: now,
      setId: entry.setId,
      contractId: entry.contractId,
      planVersion: 0,
      queueEntryId: entry.id,
      verdictEvidence: entry.verdictEvidence,
    );

    // 6. Append SANCTION_DISPUTED to the ledger (INV-1, Pillar C)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 7. Update queue entry status to disputed
    final updated = entry.copyWith(
      status: SanctionReviewStatus.disputed,
      reviewedAtUtc: now,
      reviewedByUserId: command.disputedByUserId,
    );
    await _queueRepo.updateStatus(updated);
  }
}
