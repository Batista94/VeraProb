import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contract_financial_amendment.dart';
import 'package:veraprob/domain/sla_audit/i_contract_financial_amendment_repository.dart';

class _FakeAmendments implements IContractFinancialAmendmentRepository {
  final List<ContractFinancialAmendment> store = [];
  Map<String, Object?>? lastAmend;

  @override
  Future<void> amendContractFinancialTerms({
    required String organizationId,
    required String contractId,
    int? financialCeilingCents,
    required int penaltyMultiplierBps,
    required DateTime effectiveAtUtc,
    String? notes,
  }) async {
    lastAmend = {
      'organizationId': organizationId,
      'contractId': contractId,
      'financialCeilingCents': financialCeilingCents,
      'penaltyMultiplierBps': penaltyMultiplierBps,
      'effectiveAtUtc': effectiveAtUtc,
      'notes': notes,
    };
    store.add(
      ContractFinancialAmendment.create(
        id: 'a-${store.length}',
        organizationId: organizationId,
        contractId: contractId,
        financialCeilingCents: financialCeilingCents,
        penaltyMultiplierBps: penaltyMultiplierBps,
        effectiveAtUtc: effectiveAtUtc,
        amendedAtUtc: effectiveAtUtc,
        notes: notes,
      ),
    );
  }

  @override
  Future<List<ContractFinancialAmendment>> getAmendmentsForContract(
    String contractId, {
    required String organizationId,
  }) async => store
      .where(
        (a) => a.contractId == contractId && a.organizationId == organizationId,
      )
      .toList();
}

void main() {
  group('IContractFinancialAmendmentRepository (port contract)', () {
    test('amend records terms; history reads them back', () async {
      final repo = _FakeAmendments();
      await repo.amendContractFinancialTerms(
        organizationId: 'org-1',
        contractId: 'c-1',
        financialCeilingCents: 5000000,
        penaltyMultiplierBps: 15000,
        effectiveAtUtc: DateTime.utc(2026, 6, 1),
        notes: 'Q2',
      );
      expect(repo.lastAmend!['penaltyMultiplierBps'], 15000);
      final history = await repo.getAmendmentsForContract(
        'c-1',
        organizationId: 'org-1',
      );
      expect(history.single.financialCeilingCents, 5000000);
    });

    test('null ceiling ("sem teto") is allowed', () async {
      final repo = _FakeAmendments();
      await repo.amendContractFinancialTerms(
        organizationId: 'org-1',
        contractId: 'c-1',
        penaltyMultiplierBps: 10000,
        effectiveAtUtc: DateTime.utc(2026, 6, 1),
      );
      final history = await repo.getAmendmentsForContract(
        'c-1',
        organizationId: 'org-1',
      );
      expect(history.single.financialCeilingCents, isNull);
    });
  });
}
