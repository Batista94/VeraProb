import '../../domain/enums/user_role.dart';

/// Command to approve a recommended sanction from the audit queue.
class ApproveSanctionCommand {
  final String queueEntryId;
  final String approvedByUserId;
  final UserRole callerRole;
  final String organizationId;

  const ApproveSanctionCommand({
    required this.queueEntryId,
    required this.approvedByUserId,
    required this.callerRole,
    required this.organizationId,
  });
}
