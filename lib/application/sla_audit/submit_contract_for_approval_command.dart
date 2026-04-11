import 'package:veraprob/domain/enums/user_role.dart';

/// Immutable command DTO for submitting a draft [Contract] for contractor approval.
///
/// Contains ZERO logic. Carries only the data required by
/// [SubmitContractForApprovalHandler] to transition the contract to
/// [awaitingContractorAcceptance] and generate a review token.
///
/// [organizationId] and [callerRole] must be injected from the
/// authenticated JWT — never from form input.
class SubmitContractForApprovalCommand {
  final String organizationId;
  final String contractId;

  /// ID of the user issuing the command (for audit trail).
  final String callerUserId;

  /// Role of the user — sourced from JWT claim, never from user input.
  final UserRole callerRole;

  /// Session ID for tenant validation.
  final String sessionId;

  const SubmitContractForApprovalCommand({
    required this.organizationId,
    required this.contractId,
    required this.callerUserId,
    required this.callerRole,
    required this.sessionId,
  });
}
