import 'contractual_service_input.dart';

/// Immutable command DTO for declaring a contractual operational plan.
///
/// Contains ZERO logic. Carries only the data required by the
/// [DeclareContractualPlanHandler] to create a [PlanDeclaration] aggregate.
///
/// Does NOT extend [OperationalCommand] — plan declaration is an
/// administrative setup action, not a real-time operational mutation.
class DeclareContractualPlanCommand {
  final String organizationId;
  final String contractId;
  final String declaredByUserId;
  final int planVersion;
  final String originalFileHash;
  final DateTime declaredAtUtc;
  final List<ContractualServiceInput> services;

  const DeclareContractualPlanCommand({
    required this.organizationId,
    required this.contractId,
    required this.declaredByUserId,
    required this.planVersion,
    required this.originalFileHash,
    required this.declaredAtUtc,
    required this.services,
  });
}
