import 'package:test/test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_delta.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

void main() {
  group('SandboxSimulationSessionDelta', () {
    SandboxSimulationSession createSession(int deltaCents) {
      return SandboxSimulationSession(
        id: 'test',
        organizationId: 'org',
        contractId: 'contract',
        sessionLabel: 'label',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
        overridesSnapshot: const SandboxSimulationOverrides(),
        baselineTotalFines: const Money(1000),
        simulatedTotalFines: Money(1000 - deltaCents),
        deltaCents: deltaCents,
        baselineEventCount: 1,
        createdByUserId: 'user',
        createdAtUtc: DateTime.utc(2026, 1, 1),
        expiresAtUtc: DateTime.utc(2030, 1, 1),
      );
    }

    test('calculates savings correctly (positive deltaCents)', () {
      final session = createSession(500); // 500 cents savings
      expect(session.deltaAmount, const Money(500));
      expect(session.direction, SandboxDeltaDirection.savings);
    });

    test('calculates increase correctly (negative deltaCents)', () {
      final session = createSession(-200); // Fines increased by 200 cents
      expect(session.deltaAmount, const Money(200)); // Absolute value
      expect(session.direction, SandboxDeltaDirection.increase);
    });

    test('calculates neutral correctly (zero deltaCents)', () {
      final session = createSession(0);
      expect(session.deltaAmount, const Money(0));
      expect(session.direction, SandboxDeltaDirection.neutral);
    });
  });
}
