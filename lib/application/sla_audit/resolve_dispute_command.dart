import 'package:veraprob/domain/enums/user_role.dart';

/// The three arcs out of a `disputed` sanction, decided by the auditor.
///
/// - [accept]: the contractor's justification is accepted → `disputed → rejected`
///   (penalty inhibited; reason persisted for the Concluídos tab).
/// - [overturn]: the justification is refused → `disputed → applied`
///   (penalty sealed; `DISPUTE_OVERTURNED` is the forensic anchor).
/// - [retract]: the dispute request is cancelled → `disputed → pending`
///   (card returns to the queue; review fields cleared).
enum DisputeResolution { accept, overturn, retract }

/// Command to resolve a disputed sanction from the audit queue.
///
/// Carries actor credentials and the session id to enforce strict tenant
/// isolation (INV-1, INV-22) at the application boundary.
class ResolveDisputeCommand {
  final String queueEntryId;
  final DisputeResolution resolution;
  final String resolvedByUserId;
  final String actorEmail;

  /// Rationale for the resolution. Required (>= 10 chars after trim) for
  /// [DisputeResolution.accept] and [DisputeResolution.overturn]; optional for
  /// [DisputeResolution.retract].
  final String? resolutionReason;

  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const ResolveDisputeCommand({
    required this.queueEntryId,
    required this.resolution,
    required this.resolvedByUserId,
    required this.actorEmail,
    required this.resolutionReason,
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
