import 'package:veraprob/domain/enums/user_role.dart';

/// Command to decline a `pending_peer_review` item, reverting it to its origin
/// status (`pending` or `disputed`). Permitted to any auditor — including the
/// first reviewer withdrawing their own request (a withdrawal is not fraud).
class DeclinePeerReviewCommand {
  final String queueEntryId;
  final String declinedByUserId;
  final String actorEmail;

  /// Optional context recorded on the `PEER_REVIEW_DECLINED` ledger fact.
  final String reason;

  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const DeclinePeerReviewCommand({
    required this.queueEntryId,
    required this.declinedByUserId,
    required this.actorEmail,
    required this.reason,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
