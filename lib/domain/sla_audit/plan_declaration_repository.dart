import 'contractual_service_execution.dart';
import 'plan_declaration.dart';

/// Domain Port: Repository for persisting and querying [PlanDeclaration] aggregates.
///
/// This interface belongs to the `sla_audit` subdomain's Domain Layer.
/// Implementations live in Infrastructure.

abstract class PlanDeclarationRepository {
  /// Persists a [PlanDeclaration] aggregate.
  Future<void> save(PlanDeclaration plan);

  /// Retrieves a [PlanDeclaration] by its unique ID.
  /// Returns `null` if not found.
  Future<PlanDeclaration?> findById(String id);

  /// Retrieves all [PlanDeclaration]s for a given contract,
  /// scoped to [organizationId].
  /// Returns an unmodifiable list.
  Future<List<PlanDeclaration>> findByContract(
    String contractId, {
    required String organizationId,
  });

  /// Retrieves all [PlanDeclaration]s for a given organization.
  /// Used by [ShiftProjectionService.ensureProjected] during the operator boot check.
  Future<List<PlanDeclaration>> findByOrganization(String organizationId);

  /// Persists projected [ContractualServiceExecution] instances for a plan.
  ///
  /// Uses upsert semantics — idempotent. Duplicate projected SETs (same
  /// plan + pattern + date) are silently ignored via the DB unique constraint.
  /// Called by [DeclareContractualPlanHandler] after eager 30-day projection.
  Future<void> saveProjectedSets(
    String planDeclarationId,
    List<ContractualServiceExecution> sets, {
    required String organizationId,
  });
}
