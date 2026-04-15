import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'contractual_financial_impact.dart';
import 'contractual_financial_impact_query_service.dart';

/// Snapshot-based implementation of [ContractualFinancialImpactQueryService].
///
/// Reads exclusively from [ContractualFinancialSnapshotRepository].
/// Aggregates all snapshots into a single impact view.
/// No fallback to ExecutionStates.
class ContractualFinancialImpactQueryServiceInMemory
    implements ContractualFinancialImpactQueryService {
  final ContractualFinancialSnapshotRepository _snapshotRepo;
  final IDateTimeProvider _clock;

  ContractualFinancialImpactQueryServiceInMemory({
    required ContractualFinancialSnapshotRepository snapshotRepo,
    required IDateTimeProvider clock,
  }) : _snapshotRepo = snapshotRepo,
       _clock = clock;

  @override
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    final snapshots = await _snapshotRepo.findAll(
      organizationId: organizationId,
      contractId: contractId,
    );

    // Filter by operational date window when provided
    final filtered = snapshots.where((s) {
      if (startUtc != null && s.operationalDateUtc.isBefore(startUtc.toUtc())) {
        return false;
      }
      if (endUtc != null && s.operationalDateUtc.isAfter(endUtc.toUtc())) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return ContractualFinancialImpact(
        contractId: contractId,
        generatedAtUtc: _clock.nowUtc(),
        totalContractedRevenue: 0,
        protectedRevenue: 0,
        revenueAtRisk: 0,
        lostRevenue: 0,
        riskPercentageBps: 0,
        lossPercentageBps: 0,
      );
    }

    // Use the latest snapshot as the current impact
    final sorted = List.of(filtered)
      ..sort((a, b) => a.operationalDateUtc.compareTo(b.operationalDateUtc));
    final latest = sorted.last;

    return ContractualFinancialImpact(
      contractId: contractId,
      generatedAtUtc: latest.closedAtUtc,
      totalContractedRevenue: latest.totalContractedRevenue.cents,
      protectedRevenue: latest.protectedRevenue.cents,
      revenueAtRisk: latest.revenueAtRisk.cents,
      lostRevenue: latest.lostRevenue.cents,
      riskPercentageBps: latest.riskPercentageBps,
      lossPercentageBps: latest.lossPercentageBps,
    );
  }
}
