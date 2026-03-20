import '../../domain/enums/user_role.dart';

/// Command to reject a recommended sanction from the audit queue.
class RejectSanctionCommand {
  final String queueEntryId;
  final String rejectedByUserId;
  final String rejectionReason;
  final UserRole callerRole;
  final String organizationId;

  const RejectSanctionCommand({
    required this.queueEntryId,
    required this.rejectedByUserId,
    required this.rejectionReason,
    required this.callerRole,
    required this.organizationId,
  });
}
