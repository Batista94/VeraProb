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

  /// Signed URLs (or storage paths) for each uploaded evidence file. Used by
  /// the server-orchestrated [ContextualSignatureAnalyzer] in the handler to
  /// perform the two-pass forensic scan before persistence (INV-13, INV-18).
  final List<String> evidenceUrls;

  /// Session ID for tenant validation.
  final String sessionId;

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
    required this.evidenceUrls,
    required this.sessionId,
  });
}
