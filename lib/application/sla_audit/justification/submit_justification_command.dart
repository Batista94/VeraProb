import 'package:veraprob/domain/enums/user_role.dart';

/// Command to submit a new contractor justification.
///
/// [callerRole] is null on the tokenized driver self-service path.
/// [submittedByTokenId] is non-null on the driver path; null on operator path.
class SubmitJustificationCommand {
  final String organizationId;
  final String contractId;
  final String setId;
  final int planVersion;
  final String category;
  final String description;
  final UserRole? callerRole;
  final String? callerUserId;
  final String? callerEmail;
  final String? submittedByTokenId;
  final List<String> evidenceHashes;

  const SubmitJustificationCommand({
    required this.organizationId,
    required this.contractId,
    required this.setId,
    required this.planVersion,
    required this.category,
    required this.description,
    required this.callerRole,
    required this.callerUserId,
    required this.callerEmail,
    required this.submittedByTokenId,
    required this.evidenceHashes,
  });
}
