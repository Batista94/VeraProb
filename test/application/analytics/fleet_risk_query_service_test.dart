import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/fleet_risk_query_service.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/domain/shared/money.dart';

class _FakeFleetRisk implements FleetRiskQueryService {
  int? lastLimit;
  final List<FleetRiskWindow> result;
  _FakeFleetRisk(this.result);

  @override
  Future<List<FleetRiskWindow>> listFleetRisk({
    required String organizationId,
    int limit = 10,
  }) async {
    lastLimit = limit;
    return result;
  }
}

FleetRiskWindow _window(int riskBps) => FleetRiskWindow(
  setId: 'set-1',
  contractId: 'c-1',
  windowStartUtc: DateTime.utc(2026, 6, 1, 8),
  windowEndUtc: DateTime.utc(2026, 6, 1, 10),
  riskBps: riskBps,
  contractualValue: const Money(150000),
);

void main() {
  group('FleetRiskQueryService (port contract)', () {
    test('default limit is 10', () async {
      final svc = _FakeFleetRisk(const []);
      await svc.listFleetRisk(organizationId: 'org-1');
      expect(svc.lastLimit, 10);
    });

    test('returns server-ranked windows', () async {
      final svc = _FakeFleetRisk([_window(9000)]);
      final rows = await svc.listFleetRisk(organizationId: 'org-1');
      expect(rows.single.riskBps, 9000);
    });

    test('FleetRiskWindow.fromJson maps risk bps + Money + UTC windows', () {
      final w = FleetRiskWindow.fromJson({
        'set_id': 'set-1',
        'contract_id': 'c-1',
        'window_start_utc': '2026-06-01T08:00:00Z',
        'window_end_utc': '2026-06-01T10:00:00Z',
        'risk_bps': 8500,
        'contractual_value_cents': 150000,
      });
      expect(w.riskBps, 8500);
      expect(w.contractualValue, const Money(150000));
      expect(w.windowStartUtc.isUtc, isTrue);
    });
  });
}
