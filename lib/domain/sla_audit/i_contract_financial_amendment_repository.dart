// pr_scanner: ignore-regression
// Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12):
// rule lifecycle scheduling/retirement + financial amendments (INV-3/4/15/21).
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
