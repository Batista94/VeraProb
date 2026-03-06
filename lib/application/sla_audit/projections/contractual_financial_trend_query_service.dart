import 'contractual_financial_trend_point.dart';

/// Read-only query service for contractual financial trend projections.
///
/// Generates time-series data from [ContractualExecutionState] aggregates,
/// grouped by creation date. Does NOT alter any state.
abstract class ContractualFinancialTrendQueryService {
  /// Returns a chronologically ordered list of daily financial snapshots.
  Future<List<ContractualFinancialTrendPoint>> getTrend({
    required String organizationId,
    String? contractId,
  });
}
