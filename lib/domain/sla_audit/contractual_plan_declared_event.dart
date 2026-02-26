import 'domain_event.dart';

/// Domain event emitted when a [PlanDeclaration] aggregate is created.
///
/// Captures the essential facts of the declaration for downstream
/// consumers (projections, ledger, audit trail).
class ContractualPlanDeclaredEvent extends DomainEvent {
  final String planDeclarationId;
  final String contractId;
  final DateTime declaredAtUtc;
  final String declaredByUserId;
  final int planVersion;
  final int totalServicesDeclared;

  const ContractualPlanDeclaredEvent({
    required super.occurredAtUtc,
    required this.planDeclarationId,
    required this.contractId,
    required this.declaredAtUtc,
    required this.declaredByUserId,
    required this.planVersion,
    required this.totalServicesDeclared,
  });
}
