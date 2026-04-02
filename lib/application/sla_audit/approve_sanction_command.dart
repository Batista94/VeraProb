import '../../domain/enums/user_role.dart';

/// Command to seal a recommended sanction from the audit queue.
///
/// Pillar C (Audit Trail): [actorEmail] is logged alongside [approvedByUserId]
/// in the immutable ledger for forensic traceability.
class ApproveSanctionCommand {
  final String queueEntryId;
  final String approvedByUserId;
  final String actorEmail;
  final UserRole callerRole;
  final String organizationId;

  const ApproveSanctionCommand({
    required this.queueEntryId,
    required this.approvedByUserId,
    required this.actorEmail,
    required this.callerRole,
    required this.organizationId,
  });
}
