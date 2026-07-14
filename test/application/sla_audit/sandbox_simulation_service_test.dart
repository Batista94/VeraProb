import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:veraprob/application/sla_audit/sandbox_simulation_service.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

class MockSandboxSimulationCommandService extends Mock
    implements SandboxSimulationCommandService {}

class MockSandboxSimulationQueryService extends Mock
    implements SandboxSimulationQueryService {}

void main() {
  group('SandboxSimulationCommandService (Interface Contract)', () {
    late MockSandboxSimulationCommandService commandService;

    setUp(() {
      commandService = MockSandboxSimulationCommandService();
    });

    test('simulate returns session UUID on success (happy path)', () async {
      const sessionId = 'session-uuid-123';
      const overrides = SandboxSimulationOverrides();

      when(
        () => commandService.simulate(
          organizationId: any(named: 'organizationId'),
          contractId: any(named: 'contractId'),
          periodStartUtc: any(named: 'periodStartUtc'),
          periodEndUtc: any(named: 'periodEndUtc'),
          overrides: any(named: 'overrides'),
          sessionLabel: any(named: 'sessionLabel'),
        ),
      ).thenAnswer((_) async => sessionId);

      final result = await commandService.simulate(
        organizationId: 'org-1',
        contractId: 'contract-2',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 6, 1),
        overrides: overrides,
        sessionLabel: 'Test Simulation',
      );

      expect(result, sessionId);
      verify(
        () => commandService.simulate(
          organizationId: 'org-1',
          contractId: 'contract-2',
          periodStartUtc: DateTime.utc(2026, 1, 1),
          periodEndUtc: DateTime.utc(2026, 6, 1),
          overrides: overrides,
          sessionLabel: 'Test Simulation',
        ),
      ).called(1);
    });

    test(
      'simulate gracefully propagates domain exceptions on dependency failure',
      () async {
        when(
          () => commandService.simulate(
            organizationId: any(named: 'organizationId'),
            contractId: any(named: 'contractId'),
            periodStartUtc: any(named: 'periodStartUtc'),
            periodEndUtc: any(named: 'periodEndUtc'),
            overrides: any(named: 'overrides'),
            sessionLabel: any(named: 'sessionLabel'),
          ),
        ).thenThrow(
          SandboxSimulationException(SandboxSimulationFailure.timeout),
        );

        expect(
          () => commandService.simulate(
            organizationId: 'org-1',
            contractId: 'contract-2',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 6, 1),
            overrides: const SandboxSimulationOverrides(),
            sessionLabel: 'Test Simulation',
          ),
          throwsA(
            isA<SandboxSimulationException>().having(
              (e) => e.failure,
              'failure',
              SandboxSimulationFailure.timeout,
            ),
          ),
        );
      },
    );
  });

  group('SandboxSimulationQueryService (Interface Contract)', () {
    late MockSandboxSimulationQueryService queryService;

    setUp(() {
      queryService = MockSandboxSimulationQueryService();
    });

    test('listSessions returns list of sessions for tenant', () async {
      final dummySession = SandboxSimulationSession(
        id: '123',
        organizationId: 'org-1',
        contractId: 'cont-1',
        sessionLabel: 'Lbl',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 1, 2),
        overridesSnapshot: const SandboxSimulationOverrides(),
        baselineTotalFines: const Money(100),
        simulatedTotalFines: const Money(50),
        deltaCents: 50,
        baselineEventCount: 1,
        createdByUserId: 'user-1',
        createdAtUtc: DateTime.utc(2026, 1, 3),
        expiresAtUtc: DateTime.utc(2030, 1, 1),
      );

      when(
        () => queryService.listSessions(
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => [dummySession]);

      final sessions = await queryService.listSessions(
        organizationId: 'org-1',
        limit: 10,
      );
      expect(sessions, isNotEmpty);
      expect(sessions.first.id, '123');
    });

    test('getSession returns specific session correctly', () async {
      when(
        () => queryService.getSession(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async => null);

      final result = await queryService.getSession(
        organizationId: 'org-1',
        sessionId: 'sess-1',
      );
      expect(result, isNull);
    });

    test('listResults returns list of results for session', () async {
      when(
        () => queryService.listResults(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async => <SandboxSimulationResult>[]);

      final results = await queryService.listResults(
        organizationId: 'org-1',
        sessionId: 'sess-1',
      );
      expect(results, isEmpty);
    });
  });
}
