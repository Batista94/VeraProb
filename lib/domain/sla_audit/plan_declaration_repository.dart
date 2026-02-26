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

  /// Retrieves all [PlanDeclaration]s for a given contract.
  /// Returns an unmodifiable list.
  Future<List<PlanDeclaration>> findByContract(String contractId);
}
