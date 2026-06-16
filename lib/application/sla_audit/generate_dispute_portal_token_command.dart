import 'package:veraprob/domain/enums/user_role.dart';

/// Command to mint a carrier-facing portal token for a contested sanction.
///
/// Pillar C (Audit Trail): [actorEmail] is logged alongside [createdByUserId]
/// in the immutable ledger (`DISPUTE_PORTAL_TOKEN_GENERATED`) for provenance.
class GenerateDisputePortalTokenCommand {
  final String queueEntryId;
  final String createdByUserId;
  final String actorEmail;
  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const GenerateDisputePortalTokenCommand({
    required this.queueEntryId,
    required this.createdByUserId,
    required this.actorEmail,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
