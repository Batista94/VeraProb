/// Immutable command DTO for cloning an existing [Contract] into a new draft.
///
/// The clone inherits [name], [contractorName] and [description] from the
/// source contract. Validity dates are intentionally omitted — the operator
/// must explicitly set them for the new contract (clone ≠ renew).
///
/// [organizationId] must be injected from the authenticated JWT —
/// never copied from the source contract (tenant isolation invariant).
class CloneContractCommand {
  /// Organization of the actor performing the clone. From JWT only.
  final String organizationId;

  /// ID of the contract to clone. Must belong to [organizationId].
  final String sourceContractId;

  /// New name for the cloned contract. Defaults to source name if not provided.
  final String name;

  final String contractorName;
  final String? description;

  const CloneContractCommand({
    required this.organizationId,
    required this.sourceContractId,
    required this.name,
    required this.contractorName,
    this.description,
  });
}
