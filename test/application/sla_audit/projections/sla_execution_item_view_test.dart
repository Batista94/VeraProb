import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1);

  SlaExecutionItemView makeView({
    ExecutionStatus status = ExecutionStatus.executed,
    int bps = 15000,
    String? plannedVehicleId,
    String? boundVehicleId,
  }) => SlaExecutionItemView(
    setId: 's1',
    contractId: 'c1',
    status: status,
    windowStartUtc: now,
    windowEndUtc: now.add(const Duration(hours: 1)),
    plannedVehicleId: plannedVehicleId,
    boundVehicleId: boundVehicleId,
    startLatitude: -23.5505,
    startLongitude: -46.6333,
    startRadiusMeters: 150,
    contractualValue: const Money(100000), // R$ 1000,00
    noShowPenaltyBps: bps,
  );

  group('SlaExecutionItemView', () {
    test('calculatedPenalty = contractualValue * bps', () {
      final view = makeView(bps: 15000);
      // 100000 cents * 1.5 = 150000 cents
      expect(view.calculatedPenalty, const Money(150000));
    });

    test('calculatedPenalty with bps 20000', () {
      final view = makeView(bps: 20000);
      expect(view.calculatedPenalty, const Money(200000));
    });

    test('props equality — same values are equal', () {
      final v1 = makeView();
      final v2 = makeView();
      expect(v1, equals(v2));
    });

    test('props inequality — different status', () {
      final v1 = makeView(status: ExecutionStatus.executed);
      final v2 = makeView(status: ExecutionStatus.noShow);
      expect(v1, isNot(equals(v2)));
    });

    test('optional fields are nullable', () {
      final view = makeView();
      expect(view.plannedVehicleId, isNull);
      expect(view.boundVehicleId, isNull);
      expect(view.boundAtUtc, isNull);
    });
  });
}
