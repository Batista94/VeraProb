import 'contract_financial_amendment.dart';

abstract class IContractFinancialAmendmentRepository {
  Future<void> amendContractFinancialTerms({
    required String contractId,
    int? financialCeilingCents,
    required int penaltyMultiplierBps,
    required DateTime effectiveAtUtc,
    String? notes,
  });

  Future<List<ContractFinancialAmendment>> getAmendmentsForContract(
    String contractId,
  );
}
