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

  /// OPTIONAL free-text complement for any arc. The structured [reasonCode] is
  /// the mandatory field for [DisputeResolution.accept] and
  /// [DisputeResolution.overturn] (Q2). For `OTHER` codes it becomes mandatory
  /// again (>= 10 chars) as the human-readable description.
  final String? resolutionReason;

  /// Structured taxonomy code from the closed `dispute_reason_codes` catalogue.
  /// Required (non-null) for accept/overturn; null for [DisputeResolution.retract].
  /// Authoritative catalogue validation happens server-side (anti-oracle, H5).
  final String? reasonCode;

  /// Attached evidence UUIDs to surface in the ledger fact. The RPC re-collects
  /// verified, non-deleted evidence authoritatively; this carries the UI's
  /// selection forward (H6).
  final List<String> evidenceIds;

  final UserRole callerRole;
  final String organizationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const ResolveDisputeCommand({
    required this.queueEntryId,
    required this.resolution,
    required this.resolvedByUserId,
    required this.actorEmail,
    this.resolutionReason,
    required this.reasonCode,
    this.evidenceIds = const [],
    required this.callerRole,
    required this.organizationId,
    required this.sessionId,
  });
}
