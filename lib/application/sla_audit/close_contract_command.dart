import '../../domain/enums/user_role.dart';

/// Immutable command DTO for closing an existing [Contract].
///
/// Contains ZERO logic. Carries only the data required by
/// [CloseContractHandler] to transition a contract to [closed].
///
/// [organizationId] and [callerRole] must be injected from the
/// authenticated JWT — never from form input.
class CloseContractCommand {
  final String organizationId;
  final String contractId;
  final String closedByUserId;
  final String reason;

  /// The role of the user issuing this command.
  /// Must be sourced from [currentUserRoleProvider] (JWT claim) — never
  /// from user input. Used by [CloseContractHandler] to enforce RBAC
  /// before any I/O is performed.
  final UserRole callerRole;

  const CloseContractCommand({
    required this.organizationId,
    required this.contractId,
    required this.closedByUserId,
    required this.reason,
    required this.callerRole,
  });
}
