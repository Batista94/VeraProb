/// Immutable command DTO for closing an existing [Contract].
///
/// Contains ZERO logic. Carries only the data required by
/// [CloseContractHandler] to transition a contract to [closed].
///
/// Note (CR-1): The UI button for this action is deferred to Phase 6
/// when RBAC is available. The domain and handler are implemented now
/// so the invariant is enforced at the domain level from Phase 5 onward.
///
/// [organizationId] must be injected from the authenticated JWT —
/// never from form input.
class CloseContractCommand {
  final String organizationId;
  final String contractId;
  final String closedByUserId;
  final String reason;

  const CloseContractCommand({
    required this.organizationId,
    required this.contractId,
    required this.closedByUserId,
    required this.reason,
  });
}
