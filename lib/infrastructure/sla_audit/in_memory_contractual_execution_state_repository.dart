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
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    final results = _store.values.where((s) {
      return s.organizationId == organizationId &&
          s.status == ExecutionStatus.pending &&
          s.contractId == contractId &&
          !s.windowStartUtc.isAfter(nowUtc) &&
          !s.windowEndUtc.isBefore(nowUtc);
    }).toList();

    return UnmodifiableListView(results);
  }

  @override
  Future<List<ContractualExecutionState>> findPendingInWindow(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    final results = _store.values.where((s) {
      return s.organizationId == organizationId &&
          s.status == ExecutionStatus.pending &&
          !s.windowStartUtc.isAfter(nowUtc) &&
          !s.windowEndUtc.isBefore(nowUtc);
    }).toList();

    return UnmodifiableListView(results);
  }

  @override
  Future<List<ContractualExecutionState>> findExpiredPending(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    final results = _store.values.where((s) {
      return s.organizationId == organizationId &&
          s.status == ExecutionStatus.pending &&
          s.windowEndUtc.isBefore(nowUtc);
    }).toList();

    return UnmodifiableListView(results);
  }

  @override
  Future<List<ContractualExecutionState>> findAll({
    required String organizationId,
  }) async {
    final results = _store.values
        .where((s) => s.organizationId == organizationId)
        .toList();
    return UnmodifiableListView(results);
  }

  @override
  Future<List<ContractualExecutionState>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    final results = _store.values
        .where(
          (s) => s.organizationId == organizationId && s.contractId == contractId,
        )
        .toList();

    return UnmodifiableListView(results);
  }
}
