import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/breach_risk_view.dart';

void main() {
  group('BreachRiskView', () {
    test('can be constructed with required fields', () {
      final view = BreachRiskView(
        riskBps: 7500,
        riskLevel: 'moderate',
        requiresPulse: false,
        windowStartUtc: DateTime.utc(2026, 3, 1),
        windowEndUtc: DateTime.utc(2026, 3, 31),
        evaluatedAtUtc: DateTime.utc(2026, 4, 1),
      );
      expect(view.riskBps, 7500);
      expect(view.riskLevel, 'moderate');
    });

    test('riskBps is int (BPS compliance — 10000 = 100%)', () {
      final view = BreachRiskView(
        riskBps: 10000,
        riskLevel: 'breached',
        requiresPulse: true,
        windowStartUtc: DateTime.utc(2026, 3, 1),
        windowEndUtc: DateTime.utc(2026, 3, 31),
        evaluatedAtUtc: DateTime.utc(2026, 4, 1),
      );
      expect(view.riskBps, isA<int>());
      expect(view.riskBps, 10000);
    });

    test('riskLevel safe = 0 risk', () {
      final view = BreachRiskView(
        riskBps: 0,
        riskLevel: 'safe',
        requiresPulse: false,
        windowStartUtc: DateTime.utc(2026, 3, 1),
        windowEndUtc: DateTime.utc(2026, 3, 31),
        evaluatedAtUtc: DateTime.utc(2026, 4, 1),
      );
      expect(view.riskBps, 0);
      expect(view.riskLevel, 'safe');
    });
  });
}
