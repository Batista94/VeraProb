import '../../../domain/shared/money.dart';
import '../../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
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

  ContractualFinancialImpactQueryServiceInMemory({
    required ContractualFinancialSnapshotRepository snapshotRepo,
  }) : _snapshotRepo = snapshotRepo;

  @override
  Future<ContractualFinancialImpact> getImpact({String? contractId}) async {
    final snapshots = await _snapshotRepo.findAll(contractId: contractId);

    if (snapshots.isEmpty) {
      return ContractualFinancialImpact(
        contractId: contractId,
        generatedAtUtc: DateTime.now().toUtc(),
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        riskPercentage: 0.0,
        lossPercentage: 0.0,
      );
    }

    // Use the latest snapshot as the current impact
    final sorted = List.of(snapshots)
      ..sort((a, b) => a.operationalDateUtc.compareTo(b.operationalDateUtc));
    final latest = sorted.last;

    return ContractualFinancialImpact(
      contractId: contractId,
      generatedAtUtc: latest.closedAtUtc,
      totalContractedRevenue: latest.totalContractedRevenue,
      protectedRevenue: latest.protectedRevenue,
      revenueAtRisk: latest.revenueAtRisk,
      lostRevenue: latest.lostRevenue,
      riskPercentage: latest.riskPercentage,
      lossPercentage: latest.lossPercentage,
    );
  }
}
