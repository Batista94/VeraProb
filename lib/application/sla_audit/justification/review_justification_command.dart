import 'package:veraprob/domain/enums/user_role.dart';

/// Base command for approve/reject justification flows.
class ApproveJustificationCommand {
  final String justificationId;
  final String organizationId;
  final int planVersion;
  final UserRole callerRole;
  final String callerUserId;
  final String callerEmail;

  const ApproveJustificationCommand({
    required this.justificationId,
    required this.organizationId,
    required this.planVersion,
    required this.callerRole,
    required this.callerUserId,
    required this.callerEmail,
  });
}

class RejectJustificationCommand {
  final String justificationId;
  final String organizationId;
  final int planVersion;
  final UserRole callerRole;
  final String callerUserId;
  final String callerEmail;
  final String rejectionNotes;

  const RejectJustificationCommand({
    required this.justificationId,
    required this.organizationId,
    required this.planVersion,
    required this.callerRole,
    required this.callerUserId,
    required this.callerEmail,
    required this.rejectionNotes,
  });
}
