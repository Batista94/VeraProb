/// Immutable command DTO for creating a new [Contract] aggregate.
///
/// Contains ZERO logic. Carries only the data required by
/// [CreateContractHandler] to create a [Contract] in draft status.
///
/// [organizationId] must be injected from the authenticated JWT —
/// never from form input.
class CreateContractCommand {
  final String organizationId;
  final String name;
  final String contractorName;
  final String? description;
  final DateTime validFromUtc;
  final DateTime validUntilUtc;

  const CreateContractCommand({
    required this.organizationId,
    required this.name,
    required this.contractorName,
    this.description,
    required this.validFromUtc,
    required this.validUntilUtc,
  });
}
