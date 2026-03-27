import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';

void main() {
  final base = DateTime.utc(2024, 1, 1);
  final end = DateTime.utc(2024, 12, 31);
  final created = DateTime.utc(2024, 1, 1, 8);
  final activated = DateTime.utc(2024, 1, 2);

  ContractSummaryView makeView({
    ContractStatusView status = ContractStatusView.active,
    DateTime? activatedAtUtc,
    int? financialCeilingCents,
    double slaHealthPercentage = 80.0,
  }) => ContractSummaryView(
    id: 'c1',
    name: 'Test Contract',
    contractorName: 'Transportes SA',
    status: status,
    validFromUtc: base,
    validUntilUtc: end,
    createdAtUtc: created,
    activatedAtUtc: activatedAtUtc,
    planCount: 2,
    activePlanVersion: 3,
    totalSetsInProgress: 5,
    slaHealthPercentage: slaHealthPercentage,
    financialCeilingCents: financialCeilingCents,
  );

  group('ContractSummaryView', () {
    test('props includes all fields', () {
      final v1 = makeView(
        activatedAtUtc: activated,
        financialCeilingCents: 50000,
      );
      final v2 = makeView(
        activatedAtUtc: activated,
        financialCeilingCents: 50000,
      );
      expect(v1, equals(v2));
    });

    test('different status produces inequality', () {
      final v1 = makeView(status: ContractStatusView.active);
      final v2 = makeView(status: ContractStatusView.closed);
      expect(v1, isNot(equals(v2)));
    });

    test('activatedAtUtc null is handled correctly', () {
      final v = makeView();
      expect(v.activatedAtUtc, isNull);
    });

    test('financialCeilingCents null is handled correctly', () {
      final v = makeView();
      expect(v.financialCeilingCents, isNull);
    });

    test('slaHealthPercentage is stored correctly', () {
      final v = makeView(slaHealthPercentage: 95.5);
      expect(v.slaHealthPercentage, 95.5);
    });
  });
}
