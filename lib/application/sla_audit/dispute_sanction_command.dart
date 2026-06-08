import 'package:veraprob/domain/enums/user_role.dart';

/// Command to dispute a recommended sanction from the audit queue (requesting more proof).
///
/// Under the CIA Triad, includes actor credentials and session identifiers
/// to enforce strict tenant isolation (INV-1, INV-22) at the boundary.
class DisputeSanctionCommand {
  final String queueEntryId;
  final String disputedByUserId;
  final String actorEmail;
  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const DisputeSanctionCommand({
    required this.queueEntryId,
    required this.disputedByUserId,
    required this.actorEmail,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
