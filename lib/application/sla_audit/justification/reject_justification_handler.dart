import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'review_justification_command.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';

/// Application handler for [RejectJustificationCommand].
///
/// Mirrors [ApproveJustificationHandler] with the addition of [rejectionNotes]
/// validation (minimum 10 chars) and a `JUSTIFICATION_REJECTED` ledger entry.
class RejectJustificationHandler {
  final JustificationRepository _justificationRepo;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;

  RejectJustificationHandler({
    required JustificationRepository justificationRepo,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
  }) : _justificationRepo = justificationRepo,
       _ledger = ledger,
       _rbac = rbac;

  Future<void> handle(RejectJustificationCommand command) async {
    // 1. RBAC
    if (!_rbac.can(
      command.callerRole,
      UserPermission.canReviewJustifications,
    )) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Validate rejection notes
    if (command.rejectionNotes.trim().length < 10) {
      throw const DomainException(
        'Rejection notes must be at least 10 characters.',
      );
    }

    // 3. Load + tenant guard (INV-1)
    final justification = await _justificationRepo.findById(
      id: command.justificationId,
      organizationId: command.organizationId,
    );
    if (justification == null) {
      throw DomainException(
        'Justification "${command.justificationId}" not found.',
      );
    }

    // 4. Idempotency guard
    if (!justification.isPending) {
      throw DomainException(
        'Justification "${command.justificationId}" is already '
        '${justification.status.dbValue}.',
      );
    }

    final now = DateTime.now().toUtc();

    // 5. Build domain event (INV-22: actor_id + actor_email in payload)
    final event = JustificationRejectedEvent(
      organizationId: command.organizationId,
      occurredAtUtc: now,
      justificationId: command.justificationId,
      setId: justification.setId,
      contractId: justification.contractId,
      planVersion: command.planVersion,
      actorUserId: command.callerUserId,
      actorEmail: command.callerEmail,
    );

    // 6. Append JUSTIFICATION_REJECTED to the immutable ledger (INV-7)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 7. Update status
    await _justificationRepo.updateStatus(
      id: command.justificationId,
      organizationId: command.organizationId,
      status: JustificationStatus.rejected,
      reviewedByUserId: command.callerUserId,
      reviewedAtUtc: now,
    );
  }
}
