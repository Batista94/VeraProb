import 'package:veraprob/domain/enums/user_role.dart';

/// Command for the SECOND auditor to confirm a high-value verdict held in
/// `pending_peer_review` (dual-control / four-eyes, Phase 10.5 Item 2).
///
/// [confirmedByUserId] is the second auditor. The RPC binds it to the JWT `sub`
/// and rejects the call if it equals the first reviewer (reviewer2 != reviewer1).
class ConfirmPeerReviewCommand {
  final String queueEntryId;
  final String confirmedByUserId;
  final String actorEmail;
  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const ConfirmPeerReviewCommand({
    required this.queueEntryId,
    required this.confirmedByUserId,
    required this.actorEmail,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
