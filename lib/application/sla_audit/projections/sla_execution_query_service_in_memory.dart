import '../../../domain/shared/money.dart';
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
  Future<SlaExecutionSummary> getSummary({
    required String organizationId,
    String? contractId,
  }) async {
    final states = await (contractId != null
        ? _repo.findByContract(contractId, organizationId: organizationId)
        : _repo.findAll(organizationId: organizationId));

    // org filter is enforced in the repo; iterate directly
    final filteredByOrg = states;

    int pending = 0, executed = 0, noShow = 0, evidenceGap = 0;
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    for (final s in filteredByOrg) {
      switch (s.status) {
        case ExecutionStatus.pending:
          pending++;
          break;
        case ExecutionStatus.executed:
          executed++;
          protectedRevenue = protectedRevenue + s.contractualValue;
          break;
        case ExecutionStatus.noShow:
          noShow++;
          lostRevenue =
              lostRevenue + (s.contractualValue * s.noShowPenaltyMultiplier);
          break;
        case ExecutionStatus.evidenceGap:
          evidenceGap++;
          revenueAtRisk = revenueAtRisk + s.contractualValue;
          break;
      }
    }

    return SlaExecutionSummary(
      contractId: contractId,
      totalPending: pending,
      totalExecuted: executed,
      totalNoShow: noShow,
      totalEvidenceGap: evidenceGap,
      generatedAtUtc: DateTime.now().toUtc(),
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByStatus(
    ExecutionStatus status, {
    required String organizationId,
    String? contractId,
  }) async {
    final states = await (contractId != null
        ? _repo.findByContract(contractId, organizationId: organizationId)
        : _repo.findAll(organizationId: organizationId));

    // org filter is enforced in the repo; filter only by status
    final filtered =
        states
            .where((s) => s.status == status)
            .toList()
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
      contractualValue: s.contractualValue,
      noShowPenaltyMultiplier: s.noShowPenaltyMultiplier,
    );
  }
}
