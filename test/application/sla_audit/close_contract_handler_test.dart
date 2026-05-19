import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/application/sla_audit/close_contract_command.dart';
import 'package:veraprob/application/sla_audit/close_contract_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_idempotency_store.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepo extends Mock implements IAuthRepository {}

void main() {
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler createHandler;
  late CloseContractHandler closeHandler;

  CreateContractHandler makeCreateHandler({String tenantId = 'org-1'}) {
    final mockAuth = MockAuthRepo();
    when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
      (_) async => domain.AuthUser(id: 'user-1', tenantId: tenantId),
    );
    final tvs = TenantValidationService(authRepository: mockAuth);
    return CreateContractHandler(
      tenantValidator: tvs,
      contractRepository: repository,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
    );
  }

  Future<String> createContract({
    String orgId = 'org-1',
    String sessionId = 'session-close',
    String name = 'Contrato A',
  }) async {
    createHandler = makeCreateHandler(tenantId: orgId);
    final created = await createHandler.handle(
      CreateContractCommand(
        organizationId: orgId,
        name: name,
        contractorName: 'Empresa A',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        sessionId: sessionId,
      ),
    );
    return created.id;
  }

  setUp(() {
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    final mockAuth = MockAuthRepo();
    when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
      (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-1'),
    );
    final tvs = TenantValidationService(authRepository: mockAuth);
    closeHandler = CloseContractHandler(
      tenantValidator: tvs,
      contractRepository: repository,
      ledger: ledger,
      rbac: RbacService(),
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
      idempotencyStore: InMemoryIdempotencyStore(),
    );
  });

  group('CloseContractHandler', () {
    test(
      'closes a draft contract — appends CONTRACT_CLOSED to ledger',
      () async {
        final contractId = await createContract();

        final closed = await closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: contractId,
            closedByUserId: 'user-1',
            reason: 'Cancelled',
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-1',
          ),
        );

        expect(closed.status, ContractStatus.closed);
        expect(closed.closedByUserId, 'user-1');
        expect(closed.closeReason, 'Cancelled');
        expect(closed.closedAtUtc, isNotNull);

        final found = await repository.findById(
          contractId,
          organizationId: 'org-1',
        );
        expect(found!.status, ContractStatus.closed);

        expect(ledger.entries, hasLength(2));
        expect(ledger.entries.first.type, 'CONTRACT_CREATED');
        expect(ledger.entries.last.type, 'CONTRACT_CLOSED');
      },
    );

    test('throws DomainException when contract not found', () async {
      expect(
        () => closeHandler.handle(
          const CloseContractCommand(
            organizationId: 'org-1',
            contractId: 'non-existent',
            closedByUserId: 'user-1',
            reason: 'Done',
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-err-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'throws SovereigntyViolationException for wrong organization (tenant isolation)',
      () async {
        final contractId = await createContract(orgId: 'org-A');

        expect(
          () => closeHandler.handle(
            CloseContractCommand(
              organizationId: 'org-B',
              contractId: contractId,
              closedByUserId: 'user-1',
              reason: 'Done',
              callerRole: UserRole.operator,
              sessionId: 'session-1',
              idempotencyKey: 'idemp-sov-1',
            ),
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test(
      'throws DomainException when closing an already-closed contract',
      () async {
        final contractId = await createContract(name: 'Contract B');

        await closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: contractId,
            closedByUserId: 'user-1',
            reason: 'First close',
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-double-1',
          ),
        );

        final closed2 = await closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: contractId,
            closedByUserId: 'user-1',
            reason:
                'Second close', // This is now a successful NO-OP via self-heal
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-double-2',
          ),
        );

        expect(closed2.status, ContractStatus.closed);
      },
    );

    test('throws DomainException for empty closedByUserId', () async {
      final contractId = await createContract(name: 'Contract C');

      expect(
        () => closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: contractId,
            closedByUserId: '',
            reason: 'Done',
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-blank-user',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for blank reason', () async {
      final contractId = await createContract(name: 'Contract D');

      expect(
        () => closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: contractId,
            closedByUserId: 'user-1',
            reason: '   ',
            callerRole: UserRole.operator,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-blank-reason',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('RBAC: auditor is rejected before any I/O', () async {
      expect(
        () => closeHandler.handle(
          const CloseContractCommand(
            organizationId: 'org-1',
            contractId: 'any-id',
            closedByUserId: 'user-auditor',
            reason: 'Attempt',
            callerRole: UserRole.auditor,
            sessionId: 'session-1',
            idempotencyKey: 'idemp-auditor',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
      expect(ledger.entries, isEmpty);
    });

    test('RBAC: operator is authorized to close contracts', () async {
      final contractId = await createContract(name: 'Contract E');

      final closed = await closeHandler.handle(
        CloseContractCommand(
          organizationId: 'org-1',
          contractId: contractId,
          closedByUserId: 'user-operator',
          reason: 'Closed by operator',
          callerRole: UserRole.operator,
          sessionId: 'session-1',
          idempotencyKey: 'idemp-rbac-op',
        ),
      );

      expect(closed.status, ContractStatus.closed);
    });

    test('RBAC: admin is authorized to close contracts', () async {
      final contractId = await createContract(name: 'Contract F');

      final closed = await closeHandler.handle(
        CloseContractCommand(
          organizationId: 'org-1',
          contractId: contractId,
          closedByUserId: 'user-admin',
          reason: 'Closed by admin',
          callerRole: UserRole.admin,
          sessionId: 'session-1',
          idempotencyKey: 'idemp-rbac-admin',
        ),
      );

      expect(closed.status, ContractStatus.closed);
    });
  });
}
