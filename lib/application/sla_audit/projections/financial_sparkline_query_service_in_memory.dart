import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';

import 'financial_sparkline_query_service.dart';
import 'financial_sparkline_series.dart';

class FinancialSparklineQueryServiceInMemory
    implements FinancialSparklineQueryService {
  final ContractualFinancialSnapshotRepository _snapshotRepo;

  const FinancialSparklineQueryServiceInMemory({
    required ContractualFinancialSnapshotRepository snapshotRepo,
  }) : _snapshotRepo = snapshotRepo;

  @override
  Future<FinancialSparklineSeries> getSparkline({
    required String organizationId,
    required int days,
  }) async {
    final snapshots = await _snapshotRepo.findAll(
      organizationId: organizationId,
      contractId: null,
    );

    if (snapshots.isEmpty) return FinancialSparklineSeries.empty;

    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
    final filtered =
        snapshots.where((s) => s.operationalDateUtc.isAfter(cutoff)).toList()
          ..sort(
            (a, b) => a.operationalDateUtc.compareTo(b.operationalDateUtc),
          );

    return FinancialSparklineSeries(
      protectedCents: filtered.map((s) => s.protectedRevenue.cents).toList(),
      atRiskCents: filtered.map((s) => s.revenueAtRisk.cents).toList(),
      lostCents: filtered.map((s) => s.lostRevenue.cents).toList(),
      datesUtc: filtered.map((s) => s.operationalDateUtc).toList(),
    );
  }
}
