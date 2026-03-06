import 'contractual_financial_impact.dart';

/// Read-only query service for contractual financial impact projections.
///
/// Derives financial metrics exclusively from [ContractualExecutionState]
/// aggregates. Does NOT alter any state.
abstract class ContractualFinancialImpactQueryService {
  /// Returns the financial impact summary, optionally filtered by contract.
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
  });
}
