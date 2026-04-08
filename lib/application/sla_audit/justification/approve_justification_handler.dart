import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'approve_justification_command.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';

/// Application handler for [ApproveJustificationCommand].
///
/// Approving a justification transitions it to [JustificationStatus.approved].
/// The DB trigger `inhibit_execution_on_justification_approval` then sets the
/// linked `execution_states` row to `inhibited` (INV-15).
///
/// Actor identity is carried in both the ledger entry payload and the DB row
/// for full traceability (INV-22).
class ApproveJustificationHandler {
  final JustificationRepository _justificationRepo;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  ApproveJustificationHandler({
    required JustificationRepository justificationRepo,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _justificationRepo = justificationRepo,
       _ledger = ledger,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  Future<void> handle(ApproveJustificationCommand command) async {
    // 1. RBAC — only admin/operator may approve (INV-22)
    if (!_rbac.can(
      command.callerRole,
      UserPermission.canReviewJustifications,
    )) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Load + tenant guard (INV-1)
    final justification = await _justificationRepo.findById(
      id: command.justificationId,
      organizationId: command.organizationId,
    );
    if (justification == null) {
      throw DomainException(
        'Justification "${command.justificationId}" not found.',
      );
    }

    // 3. Idempotency guard — only pending can be approved
    if (!justification.isPending) {
      throw DomainException(
        'Justification "${command.justificationId}" is already '
        '${justification.status.dbValue}.',
      );
    }

    final now = _dateTimeProvider.now();

    // 4. Build domain event (INV-22: actor_id + actor_email in payload)
    final event = JustificationApprovedEvent(
      organizationId: command.organizationId,
      occurredAtUtc: now,
      justificationId: command.justificationId,
      setId: justification.setId,
      contractId: justification.contractId,
      planVersion: command.planVersion,
      actorUserId: command.callerUserId,
      actorEmail: command.callerEmail,
    );

    // 5. Append JUSTIFICATION_APPROVED to the immutable ledger (INV-7)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 6. Update status — DB trigger handles INHIBITED transition (INV-15)
    await _justificationRepo.updateStatus(
      id: command.justificationId,
      organizationId: command.organizationId,
      status: JustificationStatus.approved,
      reviewedByUserId: command.callerUserId,
      reviewedAtUtc: now,
    );
  }
}
