import 'package:veraprob/domain/enums/user_role.dart';

/// Command to refuse a recommended sanction from the audit queue.
///
/// Pillar C (Audit Trail): [actorEmail] is logged alongside [rejectedByUserId]
/// in the immutable ledger for forensic traceability.
class RejectSanctionCommand {
  final String queueEntryId;
  final String rejectedByUserId;
  final String actorEmail;
  final String rejectionReason;
  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const RejectSanctionCommand({
    required this.queueEntryId,
    required this.rejectedByUserId,
    required this.actorEmail,
    required this.rejectionReason,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
