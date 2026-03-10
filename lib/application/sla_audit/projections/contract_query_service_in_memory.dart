import '../../../domain/sla_audit/contract_repository.dart';
import '../../../domain/sla_audit/contract_status.dart';
import '../../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../../domain/sla_audit/execution_status.dart';
import '../../../domain/sla_audit/plan_declaration_repository.dart';
import 'contract_detail_view.dart';
import 'contract_query_service.dart';
import 'contract_summary_view.dart';
import 'sla_execution_item_view.dart';
import 'sla_execution_query_service.dart';

/// In-memory implementation of [ContractQueryService].
///
/// Used in tests and simulation mode. Derives projections from
/// in-memory repositories — no database access.
class ContractQueryServiceInMemory implements ContractQueryService {
  final ContractRepository _contractRepository;
  final PlanDeclarationRepository _planRepository;
  final ContractualExecutionStateRepository _executionStateRepository;
  final SlaExecutionQueryService _slaExecutionQueryService;

  ContractQueryServiceInMemory({
    required ContractRepository contractRepository,
    required PlanDeclarationRepository planRepository,
    required ContractualExecutionStateRepository executionStateRepository,
    required SlaExecutionQueryService slaExecutionQueryService,
  })  : _contractRepository = contractRepository,
        _planRepository = planRepository,
        _executionStateRepository = executionStateRepository,
        _slaExecutionQueryService = slaExecutionQueryService;

  @override
  Future<List<ContractSummaryView>> listContracts({
    required String organizationId,
    ContractStatus? status,
  }) async {
    final contracts = await _contractRepository.findByOrganization(
      organizationId,
      status: status,
    );

    final views = <ContractSummaryView>[];
    for (final contract in contracts) {
      final summary = await _buildSummary(contract.id, organizationId);
      if (summary != null) views.add(summary);
    }

    // Ordered by createdAtUtc descending
    views.sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return List.unmodifiable(views);
  }

  @override
  Future<ContractDetailView?> getContractDetail({
    required String organizationId,
    required String contractId,
  }) async {
    final summary = await _buildSummary(contractId, organizationId);
    if (summary == null) return null;

    // Recent executions — all SETs for this contract, ordered by windowStart desc
    final allStates = await _executionStateRepository.findByContract(
      contractId,
      organizationId: organizationId,
    );
    final recentExecutions = allStates
        .map(
          (s) => SlaExecutionItemView(
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
          ),
        )
        .toList()
      ..sort((a, b) => b.windowStartUtc.compareTo(a.windowStartUtc));

    // Financial summary for this contract
    final financialSummary = await _slaExecutionQueryService.getSummary(
      organizationId: organizationId,
      contractId: contractId,
    );

    return ContractDetailView(
      summary: summary,
      recentExecutions: List.unmodifiable(recentExecutions),
      financialSummary: financialSummary,
    );
  }

  // ── Private helpers ────────────────────────────────────────

  Future<ContractSummaryView?> _buildSummary(
    String contractId,
    String organizationId,
  ) async {
    final contract = await _contractRepository.findById(
      contractId,
      organizationId: organizationId,
    );
    if (contract == null) return null;

    // Plan counters
    final plans = await _planRepository.findByContract(
      contractId,
      organizationId: organizationId,
    );
    final planCount = plans.length;
    final activePlanVersion = plans.isEmpty
        ? 0
        : plans.map((p) => p.planVersion).reduce((a, b) => a > b ? a : b);

    // Execution state counters
    final allStates = await _executionStateRepository.findByContract(
      contractId,
      organizationId: organizationId,
    );
    final totalSetsInProgress =
        allStates.where((s) => s.status == ExecutionStatus.pending).length;

    // SLA health: executed / total * 100
    final totalSets = allStates.length;
    final executedCount =
        allStates.where((s) => s.status == ExecutionStatus.executed).length;
    final slaHealthPercentage =
        totalSets == 0 ? 0.0 : (executedCount / totalSets) * 100.0;

    return ContractSummaryView(
      id: contract.id,
      name: contract.name,
      contractorName: contract.contractorName,
      status: contract.status,
      validFromUtc: contract.validFromUtc,
      validUntilUtc: contract.validUntilUtc,
      createdAtUtc: contract.createdAtUtc,
      activatedAtUtc: contract.activatedAtUtc,
      planCount: planCount,
      activePlanVersion: activePlanVersion,
      totalSetsInProgress: totalSetsInProgress,
      slaHealthPercentage: slaHealthPercentage,
    );
  }
}
