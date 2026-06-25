import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';

void main() {
  group('FinancialSparklineSeries', () {
    test('empty constant has no data and reports isEmpty', () {
      expect(FinancialSparklineSeries.empty.isEmpty, isTrue);
      expect(FinancialSparklineSeries.empty.protectedCents, isEmpty);
      expect(FinancialSparklineSeries.empty.atRiskCents, isEmpty);
      expect(FinancialSparklineSeries.empty.lostCents, isEmpty);
      expect(FinancialSparklineSeries.empty.datesUtc, isEmpty);
    });

    test('isEmpty is false when dates are present', () {
      final series = FinancialSparklineSeries(
        protectedCents: const [100],
        atRiskCents: const [20],
        lostCents: const [5],
        datesUtc: [DateTime.utc(2026, 3, 1)],
      );
      expect(series.isEmpty, isFalse);
    });

    test('value equality holds for identical content (Equatable)', () {
      final a = FinancialSparklineSeries(
        protectedCents: const [100, 200],
        atRiskCents: const [10, 20],
        lostCents: const [1, 2],
        datesUtc: [DateTime.utc(2026, 3, 1), DateTime.utc(2026, 3, 2)],
      );
      final b = FinancialSparklineSeries(
        protectedCents: const [100, 200],
        atRiskCents: const [10, 20],
        lostCents: const [1, 2],
        datesUtc: [DateTime.utc(2026, 3, 1), DateTime.utc(2026, 3, 2)],
      );
      expect(a, equals(b));
    });

    test('value equality fails when a series differs', () {
      final a = FinancialSparklineSeries(
        protectedCents: const [100],
        atRiskCents: const [10],
        lostCents: const [1],
        datesUtc: [DateTime.utc(2026, 3, 1)],
      );
      final b = FinancialSparklineSeries(
        protectedCents: const [999],
        atRiskCents: const [10],
        lostCents: const [1],
        datesUtc: [DateTime.utc(2026, 3, 1)],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
