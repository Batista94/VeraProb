import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/operational_control_service.dart';
import 'package:veraprob/domain/authority/commands/contracts/update_contract_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';
import 'package:veraprob/domain/authority/repositories/forensic_decision_repository.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

// REQUISITO (AuditÃ¡vel): Mocks estritamente via Mocktail
class MockPolicyEvaluator extends Mock implements AuthorityPolicyEvaluator {}

class MockForensicRepository extends Mock
    implements ForensicDecisionRepository {}

class MockControlService extends Mock implements OperationalControlService {}

// Fallbacks para o Mocktail (any(), captureAny())
class FakeAuthorizationContext extends Fake implements AuthorizationContext {}

class FakeOperationalActionType extends Fake implements OperationalActionType {}

class FakeTargetRef extends Fake implements TargetRef {}

class FakeAuthorizationDecision extends Fake implements AuthorizationDecision {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthorizationContext());
    registerFallbackValue(FakeOperationalActionType());
    registerFallbackValue(FakeTargetRef());
    registerFallbackValue(FakeAuthorizationDecision());
  });

  group('Red Team Security Audit: AuthorizingCommandBus', () {
    late MockPolicyEvaluator evaluator;
    late MockForensicRepository repository;
    late MockControlService controlService;
    late MockDateTimeProvider mockDateTime;

    setUp(() {
      evaluator = MockPolicyEvaluator();
      repository = MockForensicRepository();
      controlService = MockControlService();
      mockDateTime = MockDateTimeProvider();

      final testTime = DateTime.utc(2026, 4, 8, 12, 0, 0);
      when(() => mockDateTime.nowUtc()).thenReturn(testTime.toUtc());

      // Default: Registrar decisÃ£o forense sempre funciona
      when(() => repository.saveDecision(any())).thenAnswer((_) async {});
    });

    // 1. PRIVILEGE ESCALATION (Bypass de Role)
    test(
      'Security Rejection: UsuÃ¡rio com Role "Driver" tenta executar UpdateContractCommand (Admin)',
      () async {
        // Arrange
        final driverContext = AuthorizationContext(
          actorId: const ActorId('driver-007'),
          roleId: const RoleId('driver'),
          tenantId: 'Org-A',
          capturedAt: mockDateTime.nowUtc().toUtc(),
        );

        // Stub: Usando matchers genÃ©ricos com nomes explÃ­citos conforme exigido pelo Mocktail para parÃ¢metros obrigatÃ³rios nomeados
        when(
          () => evaluator.evaluate(
            actionType: any(named: 'actionType'),
            context: any(named: 'context'),
            targetRef: any(named: 'targetRef'),
            nowUtc: any(named: 'nowUtc'),
          ),
        ).thenAnswer(
          (_) async => AuthorizationDecision(
            decisionId: 'escalation-attempt-id',
            actorId: driverContext.actorId,
            roleId: driverContext.roleId,
            actionType: OperationalActionType.updateContract,
            targetRef: const TargetRef('contract', 'c-secure'),
            policyVersion: 'v1',
            result: DecisionResult.denied,
            reason: 'Policy Veto: Drivers cannot update contracts',
            occurredAt: driverContext.capturedAt,
            contextSnapshot: driverContext.toJson(),
          ),
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          repository,
          () => driverContext,
          controlService,
          mockDateTime,
        );

        const command = UpdateContractCommand(
          contractId: 'c-secure',
          newValueCents: 100000,
          targetOrganizationId: 'Org-A', // OrganizaÃ§Ã£o correta, role ERRADA
        );

        // Act & Assert
        await expectLater(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
        );

        // VETO DE EXECUÃ‡ÃƒO: O mutador nunca deve ser tocado
        verifyNever(() => controlService.updateContract(any(), any()));

        // AUDIT TRAIL: Requisito INV-9 (UTC Check)
        final captured = verify(
          () => repository.saveDecision(captureAny()),
        ).captured;
        final decision = captured.last as AuthorizationDecision;

        expect(decision.result, DecisionResult.denied);
        expect(decision.occurredAt.isUtc, isTrue);
      },
    );

    // 2. CROSS-TENANT ATTACK (Isolamento de Dados)
    test(
      'Security Rejection: Admin da Org-B tenta atualizar contrato da Org-A (Cross-Tenant Matching)',
      () async {
        // Arrange: UsuÃ¡rio autenticado na Org-B
        final orgBContext = AuthorizationContext(
          actorId: const ActorId('admin-org-b'),
          roleId: const RoleId('admin'),
          tenantId: 'Organization-B',
          capturedAt: mockDateTime.nowUtc().toUtc(),
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          repository,
          () => orgBContext,
          controlService,
          mockDateTime,
        );

        // Ataque: Tentar mudar o contrato da Org-A
        const command = UpdateContractCommand(
          contractId: 'contract-from-org-a',
          newValueCents: 5000,
          targetOrganizationId: 'Organization-A', // ALVO DE OUTRO TENANT
        );

        // Act & Assert: Veto Imediato deve ocorrer no bus antes da polÃ­tica
        await expectLater(
          () => bus.dispatch(command),
          throwsA(
            predicate(
              (e) =>
                  e is UnauthorizedActionException &&
                  e.toString().contains('Tenant Mismatch'),
            ),
          ),
        );

        // VETO IMEDIATO: O bus bloqueia antes mesmo de avaliar polÃ­tica
        verifyNever(
          () => evaluator.evaluate(
            actionType: any(named: 'actionType'),
            context: any(named: 'context'),
            targetRef: any(named: 'targetRef'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );

        verifyNever(() => controlService.updateContract(any(), any()));

        // AUDIT TRAIL: DecisÃ£o forense registrada no ledger
        final captured = verify(
          () => repository.saveDecision(captureAny()),
        ).captured;
        final decision = captured.last as AuthorizationDecision;

        expect(decision.result, DecisionResult.denied);
        expect(decision.reason, contains('CROSS-TENANT VETO'));
      },
    );

    // 4. MALFORMED/NULL CONTEXT
    test(
      'Security Rejection: Contexto nulo ou malformado impede o despacho via TypeError',
      () async {
        final bus = AuthorizingCommandBus(
          evaluator,
          repository,
          () => AuthorizationContext(
            actorId: const ActorId('bad-context'),
            roleId: const RoleId('none'),
            tenantId: null,
            capturedAt: null as dynamic, // Provoca TypeError (nÃ£o-nulo)
          ),
          controlService,
          mockDateTime,
        );

        const command = UpdateContractCommand(
          contractId: 'c-fail',
          newValueCents: 10,
          targetOrganizationId: 'Org-A',
        );

        // Act & Assert
        await expectLater(
          () => bus.dispatch(command),
          throwsA(isA<TypeError>()),
        );

        verifyNever(() => controlService.updateContract(any(), any()));
      },
    );

    // GOLDEN PATH: Admin Update (Isolamento OK e Role OK)
    test(
      'Golden Path: ExecuÃ§Ã£o autorizada quando Role e Tenant estÃ£o corretos',
      () async {
        // Arrange
        final adminContext = AuthorizationContext(
          actorId: const ActorId('admin-a'),
          roleId: const RoleId('admin'),
          tenantId: 'Org-A',
          capturedAt: mockDateTime.nowUtc().toUtc(),
        );

        when(
          () => evaluator.evaluate(
            actionType: any(named: 'actionType'),
            context: any(named: 'context'),
            targetRef: any(named: 'targetRef'),
            nowUtc: any(named: 'nowUtc'),
          ),
        ).thenAnswer(
          (_) async => AuthorizationDecision(
            decisionId: 'approved-id',
            actorId: adminContext.actorId,
            roleId: adminContext.roleId,
            actionType: OperationalActionType.updateContract,
            targetRef: const TargetRef('contract', 'c-1'),
            policyVersion: 'v1',
            result: DecisionResult.approved,
            occurredAt: adminContext.capturedAt,
            contextSnapshot: adminContext.toJson(),
          ),
        );

        when(
          () => controlService.updateContract(any(), any()),
        ).thenAnswer((_) async {});

        final bus = AuthorizingCommandBus(
          evaluator,
          repository,
          () => adminContext,
          controlService,
          mockDateTime,
        );

        const command = UpdateContractCommand(
          contractId: 'c-1',
          newValueCents: 9999,
          targetOrganizationId: 'Org-A',
        );

        // Act
        await bus.dispatch(command);

        // Assert
        verify(() => controlService.updateContract('c-1', 9999)).called(1);

        final captured = verify(
          () => repository.saveDecision(captureAny()),
        ).captured;
        expect(
          (captured.last as AuthorizationDecision).result,
          DecisionResult.approved,
        );
      },
    );
  });
}
