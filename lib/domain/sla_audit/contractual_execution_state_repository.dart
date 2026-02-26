import 'contractual_execution_state.dart';

/// Domain Port: Repository for persisting and querying
/// [ContractualExecutionState] aggregates.
///
/// Indexed by [setId] — one execution state per contractual obligation.
abstract class ContractualExecutionStateRepository {
  /// Persists or updates a [ContractualExecutionState].
  Future<void> save(ContractualExecutionState state);

  /// Retrieves the execution state for a given SET.
  /// Returns `null` if not found.
  Future<ContractualExecutionState?> findBySetId(String setId);

  /// Retrieves all pending execution states for a contract
  /// whose time window contains [nowUtc].
  ///
  /// Returns an unmodifiable list.
  Future<List<ContractualExecutionState>> findPendingByContractAndTime(
    String contractId,
    DateTime nowUtc,
  );
}
