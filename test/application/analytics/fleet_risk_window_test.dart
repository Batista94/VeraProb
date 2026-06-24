import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/domain/sla_audit/sla_breach_risk_calculator.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  Map<String, dynamic> row() => {
    'set_id': 'set-1',
    'contract_id': 'contractA',
    'window_start_utc': '2026-06-14T00:00:00+00:00',
    'window_end_utc': '2026-06-14T02:46:40+00:00', // +10000s
    'risk_bps': 5000,
    'contractual_value_cents': 100000,
  };

  group('FleetRiskWindow.fromJson', () {
    test('maps columns; timestamps normalized to UTC', () {
      final w = FleetRiskWindow.fromJson(row());
      expect(w.setId, 'set-1');
      expect(w.riskBps, 5000);
      expect(w.contractualValue, const Money(100000));
      expect(w.windowStartUtc.isUtc, isTrue);
      expect(w.windowEndUtc.difference(w.windowStartUtc).inSeconds, 10000);
    });

    test('Equatable identity', () {
      expect(FleetRiskWindow.fromJson(row()), FleetRiskWindow.fromJson(row()));
    });
  });

  group('asBreachReport', () {
    test('uses server riskBps + 15% buffer; classifies level', () {
      final w = FleetRiskWindow.fromJson(row());
      final now = DateTime.utc(2026, 6, 14, 1);
      final report = w.asBreachReport(nowUtc: now);

      // buffer = (10000*1500 + 5000) ~/ 10000 = 1500s.
      expect(report.buffer.inSeconds, 1500);
      expect(report.riskBps, 5000);
      expect(report.riskLevel, SlaRiskLevel.moderate);
      expect(report.requiresPulse, isFalse); // 5000 < 8500
      expect(report.evaluatedAtUtc, now);
    });
  });
}
