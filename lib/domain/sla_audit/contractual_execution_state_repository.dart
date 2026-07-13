// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'contractual_execution_state.dart';

/// Domain Port: Repository for persisting and querying
/// [ContractualExecutionState] aggregates.
///
/// Indexed by [setId] — one execution state per contractual obligation.
abstract class ContractualExecutionStateRepository {
  /// Persists or updates a [ContractualExecutionState].
  Future<void> save(ContractualExecutionState state);

  /// Retrieves the execution state for a given SET, org-scoped (INV-1).
  /// Returns `null` if not found or wrong org (INV-26).
  Future<ContractualExecutionState?> findBySetId(
    String setId, {
    required String organizationId,
  });

  /// Retrieves all pending execution states for a contract
  /// whose time window contains [nowUtc].
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findPlannedByContractAndTime(
    String contractId,
    DateTime nowUtc, {
    required String organizationId,
  });

  /// Retrieves all pending execution states whose time window
  /// contains [nowUtc], scoped to [organizationId].
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findPlannedInWindow(
    DateTime nowUtc, {
    required String organizationId,
  });

  /// Retrieves all execution states whose time window contains [nowUtc]
  /// and are in a state that can be re-evaluated (pending, noShow, evidenceGap).
  /// Required for INV-12 Re-evaluation Protocol.
  Future<List<ContractualExecutionState>> findActiveInWindow(
    DateTime nowUtc, {
    required String organizationId,
  });

  /// Retrieves all pending execution states whose time window
  /// has expired (windowEndUtc < [nowUtc]), scoped to [organizationId].
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findExpiredPlanned(
    DateTime nowUtc, {
    required String organizationId,
  });

  /// Retrieves all execution states for [organizationId].
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findAll({
    required String organizationId,
  });

  /// Retrieves all execution states for a given contract,
  /// scoped to [organizationId], regardless of status.
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findByContract(
    String contractId, {
    required String organizationId,
  });
}
