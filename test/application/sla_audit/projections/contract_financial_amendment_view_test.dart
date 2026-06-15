import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contract_financial_amendment_view.dart';

void main() {
  group('ContractFinancialAmendmentView.fromJson', () {
    test('parses all fields and normalizes timestamps to UTC', () {
      final v = ContractFinancialAmendmentView.fromJson({
        'id': 'a1',
        'financial_ceiling_cents': 5000000,
        'penalty_multiplier_bps': 15000,
        'effective_at_utc': '2026-06-01T12:00:00Z',
        'amended_at_utc': '2026-05-31T08:30:00Z',
        'notes': 'Renegociação Q2',
      });
      expect(v.id, 'a1');
      expect(v.financialCeilingCents, 5000000);
      expect(v.penaltyMultiplierBps, 15000);
      expect(v.effectiveAtUtc.isUtc, isTrue);
      expect(v.amendedAtUtc.isUtc, isTrue);
      expect(v.notes, 'Renegociação Q2');
    });

    test('null ceiling and notes parse to null', () {
      final v = ContractFinancialAmendmentView.fromJson({
        'id': 'a2',
        'financial_ceiling_cents': null,
        'penalty_multiplier_bps': 10000,
        'effective_at_utc': '2026-06-01T12:00:00Z',
        'amended_at_utc': '2026-06-01T12:00:00Z',
        'notes': null,
      });
      expect(v.financialCeilingCents, isNull);
      expect(v.notes, isNull);
    });
  });

  group('penaltyMultiplierLabel (pure integer bps → factor, INV-4/5)', () {
    ContractFinancialAmendmentView withBps(int bps) =>
        ContractFinancialAmendmentView(
          id: 'x',
          financialCeilingCents: null,
          penaltyMultiplierBps: bps,
          effectiveAtUtc: DateTime.utc(2026, 1, 1),
          amendedAtUtc: DateTime.utc(2026, 1, 1),
          notes: null,
        );

    test(
      '10000 → 1.00x',
      () => expect(withBps(10000).penaltyMultiplierLabel, '1.00x'),
    );
    test(
      '15000 → 1.50x',
      () => expect(withBps(15000).penaltyMultiplierLabel, '1.50x'),
    );
    test('12345 → 1.23x (truncates hundredths, no double)', () {
      expect(withBps(12345).penaltyMultiplierLabel, '1.23x');
    });
    test('20500 → 2.05x (zero-padded hundredths)', () {
      expect(withBps(20500).penaltyMultiplierLabel, '2.05x');
    });
  });

  test('value equality via Equatable props', () {
    final a = ContractFinancialAmendmentView.fromJson({
      'id': 'a1',
      'financial_ceiling_cents': 100,
      'penalty_multiplier_bps': 10000,
      'effective_at_utc': '2026-06-01T12:00:00Z',
      'amended_at_utc': '2026-06-01T12:00:00Z',
      'notes': null,
    });
    final b = ContractFinancialAmendmentView.fromJson({
      'id': 'a1',
      'financial_ceiling_cents': 100,
      'penalty_multiplier_bps': 10000,
      'effective_at_utc': '2026-06-01T12:00:00Z',
      'amended_at_utc': '2026-06-01T12:00:00Z',
      'notes': null,
    });
    expect(a, b);
  });
}
