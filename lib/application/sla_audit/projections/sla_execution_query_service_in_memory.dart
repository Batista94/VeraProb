import '../../../domain/sla_audit/contractual_execution_state.dart';
import '../../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../../domain/sla_audit/execution_status.dart';
import 'sla_execution_item_view.dart';
import 'sla_execution_query_service.dart';
import 'sla_execution_summary.dart';

/// In-memory implementation of [SlaExecutionQueryService].
///
/// Reads from [ContractualExecutionStateRepository] and maps
/// aggregates to read models. Never exposes aggregates directly.
class SlaExecutionQueryServiceInMemory implements SlaExecutionQueryService {
  final ContractualExecutionStateRepository _repo;

  SlaExecutionQueryServiceInMemory({
    required ContractualExecutionStateRepository repo,
  }) : _repo = repo;

  @override
  Future<SlaExecutionSummary> getSummary({String? contractId}) async {
    final states = contractId != null
        ? await _repo.findByContract(contractId)
        : await _repo.findAll();

    int pending = 0, executed = 0, noShow = 0, evidenceGap = 0;

    for (final s in states) {
      switch (s.status) {
        case ExecutionStatus.pending:
          pending++;
        case ExecutionStatus.executed:
          executed++;
        case ExecutionStatus.noShow:
          noShow++;
        case ExecutionStatus.evidenceGap:
          evidenceGap++;
      }
    }

    return SlaExecutionSummary(
      contractId: contractId,
      totalPending: pending,
      totalExecuted: executed,
      totalNoShow: noShow,
      totalEvidenceGap: evidenceGap,
      generatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByStatus(
    ExecutionStatus status, {
    String? contractId,
  }) async {
    final states = contractId != null
        ? await _repo.findByContract(contractId)
        : await _repo.findAll();

    final filtered = states.where((s) => s.status == status).toList()
      ..sort((a, b) => a.windowStartUtc.compareTo(b.windowStartUtc));

    return filtered.map(_toItemView).toList();
  }

  // ── Mapper ──────────────────────────────────────────────

  static SlaExecutionItemView _toItemView(ContractualExecutionState s) {
    return SlaExecutionItemView(
      setId: s.setId,
      contractId: s.contractId,
      status: s.status,
      windowStartUtc: s.windowStartUtc,
      windowEndUtc: s.windowEndUtc,
      plannedVehicleId: s.plannedVehicleId,
      boundVehicleId: s.boundVehicleId,
      boundAtUtc: s.bindingTimestampUtc,
      startLatitude: s.startLatitude,
      startLongitude: s.startLongitude,
      startRadiusMeters: s.startRadiusMeters,
    );
  }
}
