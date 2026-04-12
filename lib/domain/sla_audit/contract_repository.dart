import 'contract.dart';
import 'contract_status.dart';

/// Domain Port: Repository for persisting and querying [Contract] aggregates.
///
/// This interface belongs to the `sla_audit` subdomain's Domain Layer.
/// Implementations live in Infrastructure ([InMemoryContractRepository],
/// [PostgresContractRepository]).
///
/// All queries are scoped by [organizationId] — multi-tenancy invariant.
abstract class ContractRepository {
  /// Persists a [Contract] aggregate (insert or update).
  ///
  /// **INV-32 (Optimistic Locking):** When updating an existing aggregate,
  /// returns the contract with the new `version` assigned by the database.
  /// The caller MUST use the returned instance for any subsequent operations
  /// to avoid [ConflictException] from stale versions.
  Future<Contract> save(Contract contract);

  /// Retrieves a [Contract] by its unique ID, scoped to [organizationId].
  ///
  /// Returns `null` if not found or if the contract belongs to a different
  /// organization (tenant isolation).
  Future<Contract?> findById(String id, {required String organizationId});

  /// Retrieves all [Contract]s for a given organization.
  ///
  /// Optionally filters by [status].
  /// Returns an unmodifiable list ordered by [Contract.createdAtUtc] descending.
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  });
}
