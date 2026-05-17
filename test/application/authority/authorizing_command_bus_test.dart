import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/domain/authority/commands/contracts/update_contract_command.dart';
import 'package:veraprob/domain/authority/commands/trips/create_trip_event_command.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

import 'mocks/mock_mutator_service.dart';
import 'mocks/strict_mock_policy_evaluator.dart';

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

/// Unmapped dummy command to test error bounding
class RogueCommand extends OperationalCommand {
  const RogueCommand();
  @override
  TargetRef get targetRef => const TargetRef('system', 'rogue');
  @override
  String? get targetOrganizationId => null;
  @override
  List<Object?> get props => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Architecture Guardians: AuthorizingCommandBus', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    AuthorizationContext mockSession() => AuthorizationContext(
      actorId: const ActorId('test-actor'),
      roleId: const RoleId('test-role'),
      capturedAt: testFixTime,
    );

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());
    });

    test(
      '1. The Golden Path (Approved Mutator): Should log APPROVED and call Mutator 1 time',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-123');

        // Act
        await bus.dispatch(command);

        // Assert
        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called exactly once.',
        );
        expect(ledger.ledgerCount, 1, reason: 'Decision must be recorded.');

        final decision = ledger.testLedgerArray;
        expect(decision.first.result, DecisionResult.approved);

        expect(
          mutator.callCount,
          1,
          reason: 'Mutator must be executed when APPROVED.',
        );
      },
    );

    test(
      '2. The Iron Gate (Denied Mutator): Should log DENIED and call Mutator 0 times',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.denied,
        });

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-999');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
          reason: 'Command Bus must instantly throw Unauthorized Exception.',
        );

        // We need to wait a tick for the exception flow to settle and check counters
        await Future<void>.delayed(Duration.zero);

        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called exactly once.',
        );
        expect(
          ledger.ledgerCount,
          1,
          reason: 'The DENIED attempt MUST be forensically logged.',
        );

        final logs = ledger.testLedgerArray;
        expect(logs.first.result, DecisionResult.denied);

        expect(
          mutator.callCount,
          0,
          reason:
              'Mutator MUST NOT BE CALLED under any circumstance when DENIED.',
        );
      },
    );

    test(
      '3. The Unmapped Rogue Command: Should fail mapping, skipping Evaluator and Mutator',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({});
        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = RogueCommand();

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnimplementedError>()),
          reason: 'Mapper must reject unknown commands before Evaluation',
        );

        await Future<void>.delayed(Duration.zero);

        expect(
          evaluator.evaluationCount,
          0,
          reason: 'Evaluator never touched.',
        );
        expect(ledger.ledgerCount, 0, reason: 'Ledger never touched.');
        expect(mutator.callCount, 0, reason: 'Mutator never touched.');
      },
    );

    test(
      '4. Atomic Mutator Failure: Should still retain the APPROVED forensic log even if system crashes downstream',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        mutator.shouldThrowError = true; // Simulates backend crash mid-mutation
        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-crash');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<Exception>()),
          reason: 'Underlying service failure should bubble up.',
        );

        await Future<void>.delayed(Duration.zero);

        expect(evaluator.evaluationCount, 1);

        // CRITICAL: The decision was taken AND LOGGED before the downstream crash.
        expect(
          ledger.ledgerCount,
          1,
          reason: 'Decision was successfully appended before the exception.',
        );
        expect(
          mutator.callCount,
          1,
          reason: 'Execution started, then crashed.',
        );

        final logs = ledger.testLedgerArray;
        expect(
          logs.first.result,
          DecisionResult.approved,
        ); // It was allowed to happen.
      },
    );
  });

  // ============================================================================
  // AUTHORIZATION REJECTION SCENARIOS (Foco: Linhas 95-99 — execution block)
  // ============================================================================
  group('Authorization Rejection Scenarios', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());
    });

    test(
      '1.1 Driver attempting to resolve alert (insufficient role) — must throw UnauthorizedActionException',
      () async {
        // Arrange: Driver role has NO permission to resolve alerts
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.denied,
        });

        AuthorizationContext driverSession() => AuthorizationContext(
          actorId: const ActorId('driver-001'),
          roleId: const RoleId('driver'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          driverSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 'trip-123');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(
            isA<UnauthorizedActionException>().having(
              (e) => e.reason,
              'reason',
              contains('Denied'),
            ),
          ),
          reason: 'Driver must be rejected when trying to resolve alerts.',
        );

        await Future<void>.delayed(Duration.zero);

        // Forensic evidence: decision MUST be logged
        expect(ledger.ledgerCount, 1, reason: 'Denied attempt must be logged.');
        final decision = ledger.testLedgerArray.first;
        expect(decision.result, DecisionResult.denied);
        expect(decision.actorId.value, 'driver-001');
        expect(decision.roleId.value, 'driver');
        expect(decision.reason, isNotNull);

        // Mutator must NOT be called
        expect(mutator.callCount, 0, reason: 'Mutator never called on denial.');
      },
    );

    test(
      '1.2 Operador attempting to update contract (insufficient role) — must throw',
      () async {
        // Arrange: Operador cannot update financial contracts
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.updateContract: DecisionResult.denied,
        });

        AuthorizationContext operadorSession() => AuthorizationContext(
          actorId: const ActorId('operador-007'),
          roleId: const RoleId('operador'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          operadorSession,
          mutator,
          mockDateTime,
        );
        const command = UpdateContractCommand(
          contractId: 'ctr-999',
          newValueCents: 50000,
          targetOrganizationId: 'org_a',
        );

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
          reason: 'Operador must be rejected when updating contracts.',
        );

        await Future<void>.delayed(Duration.zero);

        expect(ledger.ledgerCount, 1);
        final decision = ledger.testLedgerArray.first;
        expect(decision.result, DecisionResult.denied);
        expect(decision.actorId.value, 'operador-007');
        expect(mutator.callCount, 0);
      },
    );

    test('1.3 Unknown role attempting any action — must throw', () async {
      // Arrange: Unknown role — explicit deny for the action being attempted
      final evaluator = StrictMockPolicyEvaluator({
        OperationalActionType.createTripEvent: DecisionResult.denied,
      });

      AuthorizationContext unknownSession() => AuthorizationContext(
        actorId: const ActorId('ghost-user'),
        roleId: const RoleId('unknown_role'),
        tenantId: 'org_x',
        capturedAt: testFixTime,
      );

      final bus = AuthorizingCommandBus(
        evaluator,
        ledger,
        unknownSession,
        mutator,
        mockDateTime,
      );
      const command = CreateTripEventCommand(
        tripId: 'trip-001',
        type: EventType.manualOverride,
      );

      // Act & Assert
      expect(
        () => bus.dispatch(command),
        throwsA(isA<UnauthorizedActionException>()),
        reason: 'Unknown role must be denied for all actions.',
      );

      await Future<void>.delayed(Duration.zero);

      expect(ledger.ledgerCount, 1);
      final decision = ledger.testLedgerArray.first;
      expect(decision.result, DecisionResult.denied);
      expect(decision.roleId.value, 'unknown_role');
      expect(mutator.callCount, 0);
    });

    test(
      '1.4 CreateTripEventCommand approved — covers CreateTripEvent execution branch (lines 95-99)',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.createTripEvent: DecisionResult.approved,
        });

        AuthorizationContext operadorSession() => AuthorizationContext(
          actorId: const ActorId('operador-evt'),
          roleId: const RoleId('operador'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          operadorSession,
          mutator,
          mockDateTime,
        );
        const command = CreateTripEventCommand(
          tripId: 'trip-evt-001',
          type: EventType.manualOverride,
        );

        // Act
        await bus.dispatch(command);

        // Assert
        expect(evaluator.evaluationCount, 1);
        expect(ledger.ledgerCount, 1);
        expect(ledger.testLedgerArray.first.result, DecisionResult.approved);
        expect(
          mutator.callCount,
          1,
          reason: 'Mutator must be called for CreateTripEvent.',
        );
      },
    );
  });

  // ============================================================================
  // TENANT CROSS-CHECK [INV-1]
  // ============================================================================
  group('Tenant Isolation [INV-1]', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());
    });

    test(
      '2.1 Admin from Org_A attempting command on Org_B — CROSS-TENANT VETO',
      () async {
        // Arrange: Admin with full permissions, but targeting wrong tenant
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        AuthorizationContext adminOrgA() => AuthorizationContext(
          actorId: const ActorId('admin-org-a'),
          roleId: const RoleId('admin'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          adminOrgA,
          mutator,
          mockDateTime,
        );
        // Command explicitly targets Org_B
        const command = ResolveAlertCommand(
          tripId: 'trip-b-001',
          targetOrganizationId: 'org_b',
        );

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(
            isA<UnauthorizedActionException>().having(
              (e) => e.reason,
              'reason',
              contains('Tenant Mismatch'),
            ),
          ),
          reason:
              'Cross-tenant command must be vetoed BEFORE policy evaluation.',
        );

        await Future<void>.delayed(Duration.zero);

        // Forensic decision MUST be logged even on cross-tenant veto
        expect(
          ledger.ledgerCount,
          1,
          reason: 'Cross-tenant veto must be forensically logged.',
        );
        final decision = ledger.testLedgerArray.first;
        expect(decision.result, DecisionResult.denied);
        expect(
          decision.reason,
          contains('CROSS-TENANT VETO'),
          reason: 'Reason must contain forensic veto message.',
        );
        expect(
          decision.reason,
          contains('org_a'),
          reason: 'Reason must include user tenant ID.',
        );
        expect(
          decision.reason,
          contains('org_b'),
          reason: 'Reason must include target tenant ID.',
        );

        // Evaluator MUST NOT be called (immediate veto)
        expect(
          evaluator.evaluationCount,
          0,
          reason: 'Evaluator must NOT be called on cross-tenant mismatch.',
        );

        // Mutator must NOT be called
        expect(mutator.callCount, 0);
      },
    );

    test(
      '2.2 Command without targetOrganizationId — proceeds to evaluator',
      () async {
        // Arrange: Command does not specify tenant — should not trigger cross-tenant check
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        AuthorizationContext adminSession() => AuthorizationContext(
          actorId: const ActorId('admin-001'),
          roleId: const RoleId('admin'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          adminSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 'trip-123');
        // No targetOrganizationId — defaults to null

        // Act
        await bus.dispatch(command);

        // Assert: Evaluator was called, command was approved
        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called when no tenant mismatch.',
        );
        expect(ledger.ledgerCount, 1);
        expect(ledger.testLedgerArray.first.result, DecisionResult.approved);
        expect(mutator.callCount, 1);
      },
    );

    test(
      '2.3 Admin from Org_A attempting command on Org_A (same tenant) — proceeds',
      () async {
        // Arrange: Command targets same tenant — should pass cross-tenant check
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.updateContract: DecisionResult.approved,
        });

        AuthorizationContext adminSession() => AuthorizationContext(
          actorId: const ActorId('admin-org-a'),
          roleId: const RoleId('admin'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          adminSession,
          mutator,
          mockDateTime,
        );
        const command = UpdateContractCommand(
          contractId: 'ctr-001',
          newValueCents: 10000,
          targetOrganizationId: 'org_a', // Same tenant
        );

        // Act
        await bus.dispatch(command);

        // Assert
        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called when tenants match.',
        );
        expect(ledger.ledgerCount, 1);
        expect(ledger.testLedgerArray.first.result, DecisionResult.approved);
        expect(mutator.callCount, 1);
      },
    );
  });

  // ============================================================================
  // SUPERADMIN LOCK [INV-6]
  // ============================================================================
  group('SuperAdmin Lock [INV-6]', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());
    });

    test(
      '3.1 UpdateContract without super_admin scope — denied by policy',
      () async {
        // Arrange: Evaluator simulates policy that requires super_admin for contracts
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.updateContract: DecisionResult.denied,
        });

        AuthorizationContext adminWithoutSuperAdmin() => AuthorizationContext(
          actorId: const ActorId('admin-no-super'),
          roleId: const RoleId('admin'),
          tenantId: 'org_a',
          scopes: [], // No super_admin scope
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          adminWithoutSuperAdmin,
          mutator,
          mockDateTime,
        );
        const command = UpdateContractCommand(
          contractId: 'ctr-critical',
          newValueCents: 999999,
          targetOrganizationId: 'org_a',
        );

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
          reason: 'Critical command without super_admin scope must be denied.',
        );

        await Future<void>.delayed(Duration.zero);

        expect(ledger.ledgerCount, 1);
        final decision = ledger.testLedgerArray.first;
        expect(decision.result, DecisionResult.denied);
        expect(decision.actorId.value, 'admin-no-super');
        expect(
          decision.contextSnapshot['scopes'],
          isEmpty,
          reason: 'Context snapshot must show no super_admin scope.',
        );
        expect(mutator.callCount, 0);
      },
    );

    test('3.2 UpdateContract WITH super_admin scope — approved', () async {
      // Arrange: Evaluator approves because user has super_admin scope
      final evaluator = StrictMockPolicyEvaluator({
        OperationalActionType.updateContract: DecisionResult.approved,
      });

      AuthorizationContext superAdminSession() => AuthorizationContext(
        actorId: const ActorId('super-admin-001'),
        roleId: const RoleId('admin'),
        tenantId: 'org_a',
        scopes: ['super_admin'], // Has super_admin claim
        capturedAt: testFixTime,
      );

      final bus = AuthorizingCommandBus(
        evaluator,
        ledger,
        superAdminSession,
        mutator,
        mockDateTime,
      );
      const command = UpdateContractCommand(
        contractId: 'ctr-critical',
        newValueCents: 999999,
        targetOrganizationId: 'org_a',
      );

      // Act
      await bus.dispatch(command);

      // Assert
      expect(
        evaluator.evaluationCount,
        1,
        reason: 'Evaluator must be called for super_admin flow.',
      );
      expect(ledger.ledgerCount, 1);
      final decision = ledger.testLedgerArray.first;
      expect(decision.result, DecisionResult.approved);
      expect(
        decision.contextSnapshot['scopes'],
        contains('super_admin'),
        reason: 'Context snapshot must record super_admin scope.',
      );
      expect(mutator.callCount, 1, reason: 'Mutator executed when approved.');
    });
  });

  // ============================================================================
  // FORENSIC AUDIT TRAIL
  // ============================================================================
  group('Forensic Audit Trail', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());
    });

    test(
      '4.1 Denied attempt logs actorId, reason, occurredAt (UTC), and contextSnapshot',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.denied,
        });

        AuthorizationContext auditorSession() => AuthorizationContext(
          actorId: const ActorId('auditor-user'),
          roleId: const RoleId('viewer'),
          tenantId: 'org_a',
          organizationId: 'org_a',
          scopes: ['read_only'],
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          auditorSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 'trip-audit-001');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
        );

        await Future<void>.delayed(Duration.zero);

        expect(ledger.ledgerCount, 1);
        final decision = ledger.testLedgerArray.first;

        // Braço NUNCA se move em cenário de negação
        expect(
          mutator.callCount,
          0,
          reason: 'Mutator MUST NOT be called on policy denial.',
        );

        // Validate all forensic fields
        expect(
          decision.actorId.value,
          'auditor-user',
          reason: 'Must log actor ID.',
        );
        expect(decision.roleId.value, 'viewer', reason: 'Must log role ID.');
        expect(decision.reason, isNotNull, reason: 'Must log denial reason.');
        expect(
          decision.occurredAt,
          testFixTime,
          reason: 'Must use deterministic UTC timestamp.',
        );
        expect(
          decision.contextSnapshot['actor_id'],
          'auditor-user',
          reason: 'Context snapshot must include actor_id.',
        );
        expect(
          decision.contextSnapshot['role_id'],
          'viewer',
          reason: 'Context snapshot must include role_id.',
        );
        expect(
          decision.contextSnapshot['tenant_id'],
          'org_a',
          reason: 'Context snapshot must include tenant_id.',
        );
        expect(
          decision.contextSnapshot['organization_id'],
          'org_a',
          reason: 'Context snapshot must include organization_id.',
        );
      },
    );

    test(
      '4.2 Cross-tenant veto logs forensic evidence with both tenant IDs in reason',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        AuthorizationContext attackerSession() => AuthorizationContext(
          actorId: const ActorId('attacker-001'),
          roleId: const RoleId('admin'),
          tenantId: 'org_evil',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          attackerSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(
          tripId: 'victim-trip',
          targetOrganizationId: 'org_victim',
        );

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
        );

        await Future<void>.delayed(Duration.zero);

        expect(ledger.ledgerCount, 1);
        final decision = ledger.testLedgerArray.first;
        expect(decision.result, DecisionResult.denied);

        // Braço NUNCA se move em cenário de cross-tenant veto
        expect(
          mutator.callCount,
          0,
          reason: 'Mutator MUST NOT be called on cross-tenant veto.',
        );

        expect(decision.reason, contains('CROSS-TENANT VETO'));
        expect(decision.reason, contains('org_evil'));
        expect(decision.reason, contains('org_victim'));
        expect(
          decision.contextSnapshot['actor_id'],
          'attacker-001',
          reason: 'Even attacker identity must be forensically logged.',
        );
      },
    );

    test(
      '4.3 occurredAt uses deterministic UTC (INV-9) — no DateTime . now() without toUtc() enforced',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.denied,
        });

        AuthorizationContext session() => AuthorizationContext(
          actorId: const ActorId('time-check'),
          roleId: const RoleId('viewer'),
          tenantId: 'org_a',
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          session,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 'trip-time');

        // Act
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
        );

        await Future<void>.delayed(Duration.zero);

        // Braço NUNCA se move em cenário de negação
        expect(
          mutator.callCount,
          0,
          reason: 'Mutator MUST NOT be called on policy denial.',
        );

        // Assert: timestamp must match our injected deterministic time
        final decision = ledger.testLedgerArray.first;
        expect(
          decision.occurredAt.isUtc,
          isTrue,
          reason: 'occurredAt MUST be UTC.',
        );
        expect(
          decision.occurredAt,
          testFixTime,
          reason: 'occurredAt MUST match injected deterministic time.',
        );
      },
    );
  });
}
