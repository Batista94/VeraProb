import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/contract_financial_amendment.dart';

void main() {
  ContractFinancialAmendment build({
    String id = 'amd-1',
    int? ceilingCents = 5000000,
    int bps = 15000,
    String? notes,
  }) {
    return ContractFinancialAmendment.create(
      id: id,
      organizationId: 'org-1',
      contractId: 'contract-1',
      financialCeilingCents: ceilingCents,
      penaltyMultiplierBps: bps,
      effectiveAtUtc: DateTime.utc(2026, 6, 12, 12),
      amendedAtUtc: DateTime.utc(2026, 6, 12, 12),
      amendedByUserId: 'user-1',
      notes: notes,
    );
  }

  group('ContractFinancialAmendment', () {
    test('create with positive bps succeeds (INV-4 INT bps)', () {
      final amendment = build();
      expect(amendment.penaltyMultiplierBps, 15000);
      expect(amendment.financialCeilingCents, 5000000);
    });

    test('create with bps = 0 throws IntegrityException (INV-10)', () {
      expect(
        () => build(bps: 0),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.field,
            'field',
            'penaltyMultiplierBps',
          ),
        ),
      );
    });

    test('create with negative bps throws IntegrityException', () {
      expect(() => build(bps: -100), throwsA(isA<IntegrityException>()));
    });

    test('null ceiling means no cap and is valid', () {
      final amendment = build(ceilingCents: null);
      expect(amendment.financialCeilingCents, isNull);
    });

    test('Equatable — identical values compare equal (all props)', () {
      expect(build(), equals(build()));
    });

    test('Equatable — differing notes break equality (props complete)', () {
      expect(build(notes: 'a'), isNot(equals(build(notes: 'b'))));
    });
  });
}
