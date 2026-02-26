import 'dart:collection';

import '../../domain/sla_audit/contractual_execution_state.dart';
import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/execution_status.dart';

/// In-memory implementation of [ContractualExecutionStateRepository].
///
/// Uses a [Map] indexed by [setId]. Save overwrites existing state.
class InMemoryContractualExecutionStateRepository
    implements ContractualExecutionStateRepository {
  final Map<String, ContractualExecutionState> _store = {};

  @override
  Future<void> save(ContractualExecutionState state) async {
    _store[state.setId] = state;
  }

  @override
  Future<ContractualExecutionState?> findBySetId(String setId) async {
    return _store[setId];
  }

  @override
  Future<List<ContractualExecutionState>> findPendingByContractAndTime(
    String contractId,
    DateTime nowUtc,
  ) async {
    final results = _store.values.where((s) {
      return s.status == ExecutionStatus.pending &&
          s.contractId == contractId &&
          !s.windowStartUtc.isAfter(nowUtc) &&
          !s.windowEndUtc.isBefore(nowUtc);
    }).toList();

    return UnmodifiableListView(results);
  }
}
