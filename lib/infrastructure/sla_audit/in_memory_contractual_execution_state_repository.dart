import 'dart:collection';

import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

/// In-memory implementation of [ContractualExecutionStateRepository].
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
  Future<List<ContractualExecutionState>> findPlannedByContractAndTime(
    String contractId,
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    return UnmodifiableListView(
      _store.values
          .where(
            (s) =>
                s.organizationId == organizationId &&
                s.status == ExecutionStatus.planned &&
                s.contractId == contractId &&
                !s.windowStartUtc.isAfter(nowUtc) &&
                !s.windowEndUtc.isBefore(nowUtc),
          )
          .toList(),
    );
  }

  @override
  Future<List<ContractualExecutionState>> findPlannedInWindow(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    return UnmodifiableListView(
      _store.values
          .where(
            (s) =>
                s.organizationId == organizationId &&
                s.status == ExecutionStatus.planned &&
                !s.windowStartUtc.isAfter(nowUtc) &&
                !s.windowEndUtc.isBefore(nowUtc),
          )
          .toList(),
    );
  }

  @override
  Future<List<ContractualExecutionState>> findActiveInWindow(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    const reevaluable = {
      ExecutionStatus.planned,
      ExecutionStatus.inTransit,
      ExecutionStatus.failed,
      ExecutionStatus.completedWithGaps,
    };
    return UnmodifiableListView(
      _store.values
          .where(
            (s) =>
                s.organizationId == organizationId &&
                reevaluable.contains(s.status) &&
                !s.windowStartUtc.isAfter(nowUtc) &&
                !s.windowEndUtc.isBefore(nowUtc),
          )
          .toList(),
    );
  }

  @override
  Future<List<ContractualExecutionState>> findExpiredPlanned(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    return UnmodifiableListView(
      _store.values
          .where(
            (s) =>
                s.organizationId == organizationId &&
                (s.status == ExecutionStatus.planned ||
                    s.status == ExecutionStatus.inTransit) &&
                s.windowEndUtc.isBefore(nowUtc),
          )
          .toList(),
    );
  }

  @override
  Future<List<ContractualExecutionState>> findAll({
    required String organizationId,
  }) async {
    return UnmodifiableListView(
      _store.values.where((s) => s.organizationId == organizationId).toList(),
    );
  }

  @override
  Future<List<ContractualExecutionState>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    return UnmodifiableListView(
      _store.values
          .where(
            (s) =>
                s.organizationId == organizationId &&
                s.contractId == contractId,
          )
          .toList(),
    );
  }
}
