import 'package:veraprob/domain/enums/user_role.dart';

/// Command to seal a recommended sanction from the audit queue.
///
/// Pillar C (Audit Trail): [actorEmail] is logged alongside [approvedByUserId]
/// in the immutable ledger for forensic traceability.
class ApproveSanctionCommand {
  final String queueEntryId;
  final String approvedByUserId;
  final String actorEmail;
  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  /// Optional structured reason code from the closed `dispute_reason_codes`
  /// taxonomy. Sealing affirms the engine's computed verdict, so a code is not
  /// mandatory — but when the auditor supplies one it is validated server-side
  /// and recorded in the `VERDICT_SEALED` ledger fact (INV-21/INV-23).
  final String? reasonCode;

  /// Optional free-text rationale accompanying the seal. Stored raw in the
  /// ledger fact; never the concurrency barrier.
  final String? reviewerReason;

  const ApproveSanctionCommand({
    required this.queueEntryId,
    required this.approvedByUserId,
    required this.actorEmail,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
    this.reasonCode,
    this.reviewerReason,
  });
}
