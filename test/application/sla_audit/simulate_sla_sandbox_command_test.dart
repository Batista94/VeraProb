import 'package:test/test.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_command.dart';

void main() {
  group('SimulateSlaSandboxCommand', () {
    test('constructs correctly and holds immutable values', () {
      final startUtc = DateTime.utc(2026, 1, 1);
      final endUtc = DateTime.utc(2026, 6, 1);
      const overrides = SandboxSimulationOverrides();

      final command = SimulateSlaSandboxCommand(
        organizationId: 'org-123',
        contractId: 'contract-456',
        periodStartUtc: startUtc,
        periodEndUtc: endUtc,
        overrides: overrides,
        sessionLabel: 'Test Simulation',
        callerRole: UserRole.operator,
        sessionId: 'session-789',
      );

      expect(command.organizationId, 'org-123');
      expect(command.contractId, 'contract-456');
      expect(command.periodStartUtc, startUtc);
      expect(command.periodEndUtc, endUtc);
      expect(command.overrides, same(overrides));
      expect(command.sessionLabel, 'Test Simulation');
      expect(command.callerRole, UserRole.operator);
      expect(command.sessionId, 'session-789');
    });

    test('enforces structural parity by accepting empty overrides', () {
      // Empty overrides are valid since they mean "evaluate baseline only"
      final command = SimulateSlaSandboxCommand(
        organizationId: 'org-123',
        contractId: 'contract-456',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 1, 31),
        overrides: const SandboxSimulationOverrides(),
        sessionLabel: 'Baseline Test',
        callerRole: UserRole.auditor,
        sessionId: 'session-789',
      );

      expect(command.overrides.overrides, isEmpty);
      expect(command.overrides.financialOverrides, isNull);
    });
  });
}
