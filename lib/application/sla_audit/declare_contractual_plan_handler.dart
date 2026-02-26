import '../../domain/sla_audit/contractual_service_execution.dart';
import '../../domain/sla_audit/plan_declaration.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'declare_contractual_plan_command.dart';

/// Application service that handles the declaration of a contractual plan.
///
/// This is a direct handler — it does NOT go through [AuthorizingCommandBus].
/// Plan declaration is an administrative setup action, not a real-time
/// operational mutation subject to RBAC/Trust Backbone policies.
///
/// The handler contains NO domain logic. All validation and entity creation
/// is delegated to domain factories:
/// - [ContractualServiceExecution.create()]
/// - [PlanDeclaration.create()]
///
/// If any [DomainException] is thrown during creation, nothing is persisted.
class DeclareContractualPlanHandler {
  final PlanDeclarationRepository _repository;
  final SlaAuditLedgerRepository _ledger;

  DeclareContractualPlanHandler({
    required PlanDeclarationRepository repository,
    required SlaAuditLedgerRepository ledger,
  }) : _repository = repository,
       _ledger = ledger;

  /// Handles the command by creating the aggregate, persisting it,
  /// and appending all domain events to the ledger.
  ///
  /// Returns the created [PlanDeclaration] aggregate.
  ///
  /// Throws [DomainException] if any invariant is violated —
  /// in which case nothing is persisted and the ledger remains untouched.
  Future<PlanDeclaration> handle(DeclareContractualPlanCommand command) async {
    // 1. Map each DTO input → domain Entity via factory
    final services = command.services
        .map(
          (input) => ContractualServiceExecution.create(
            contractId: command.contractId,
            scheduledStartTimeUtc: input.scheduledStartTimeUtc,
            scheduledEndTimeUtc: input.scheduledEndTimeUtc,
            startLatitude: input.startLatitude,
            startLongitude: input.startLongitude,
            startRadiusMeters: input.startRadiusMeters,
            endLatitude: input.endLatitude,
            endLongitude: input.endLongitude,
            endRadiusMeters: input.endRadiusMeters,
            plannedVehicleId: input.plannedVehicleId,
            contractualValue: input.contractualValue,
            noShowPenaltyMultiplier: input.noShowPenaltyMultiplier,
          ),
        )
        .toList();

    // 2. Create aggregate via domain factory
    final plan = PlanDeclaration.create(
      contractId: command.contractId,
      declaredAtUtc: command.declaredAtUtc,
      declaredByUserId: command.declaredByUserId,
      planVersion: command.planVersion,
      originalFileHash: command.originalFileHash,
      services: services,
    );

    // 3. Persist aggregate
    await _repository.save(plan);

    // 4. Append all domain events to the ledger (generic, no type casting)
    for (final event in plan.domainEvents) {
      await _ledger.append(event);
    }

    // 5. Return aggregate
    return plan;
  }
}
