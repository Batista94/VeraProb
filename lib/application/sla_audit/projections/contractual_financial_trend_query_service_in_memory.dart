import 'package:intl/intl.dart';

import '../../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'contractual_financial_trend_point.dart';
import 'contractual_financial_trend_query_service.dart';

/// Snapshot-based implementation of [ContractualFinancialTrendQueryService].
///
/// Reads exclusively from [ContractualFinancialSnapshotRepository].
/// Each trend point corresponds to a persisted daily snapshot.
/// No fallback to ExecutionStates.
class ContractualFinancialTrendQueryServiceInMemory
    implements ContractualFinancialTrendQueryService {
  final ContractualFinancialSnapshotRepository _snapshotRepo;

  ContractualFinancialTrendQueryServiceInMemory({
    required ContractualFinancialSnapshotRepository snapshotRepo,
  }) : _snapshotRepo = snapshotRepo;

  @override
  Future<List<ContractualFinancialTrendPoint>> getTrend({
    required String organizationId,
    String? contractId,
  }) async {
    final snapshots = await _snapshotRepo.findAll(
      organizationId: organizationId,
      contractId: contractId,
    );

    if (snapshots.isEmpty) return [];

    // Sort by operational date ascending
    final sorted = List.of(snapshots)
      ..sort((a, b) => a.operationalDateUtc.compareTo(b.operationalDateUtc));

    return sorted.map((snapshot) {
      final formattedDate = DateFormat(
        'dd/MM/yyyy',
        'pt_BR',
      ).format(snapshot.operationalDateUtc);

      return ContractualFinancialTrendPoint(
        dateUtc: snapshot.operationalDateUtc,
        formattedDate: formattedDate,
        baseRevenueUsedForCalculation: snapshot.totalContractedRevenue,
        totalContractedRevenue: snapshot.totalContractedRevenue,
        protectedRevenue: snapshot.protectedRevenue,
        revenueAtRisk: snapshot.revenueAtRisk,
        lostRevenue: snapshot.lostRevenue,
        riskPercentage: snapshot.riskPercentage,
        lossPercentage: snapshot.lossPercentage,
      );
    }).toList();
  }
}
