import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/clone_contract_command.dart';
import 'package:veraprob/application/sla_audit/clone_contract_handler.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

class _MockAuthRepo extends Mock implements IAuthRepository {}

void main() {
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler createHandler;
  late CloneContractHandler cloneHandler;

  final validFrom = DateTime.utc(2026, 1, 1);
  final validUntil = DateTime.utc(2026, 12, 31, 23, 59, 59);
  final cloneFrom = DateTime.utc(2026, 6, 1);
  final cloneUntil = DateTime.utc(2027, 5, 31, 23, 59, 59);

  CreateContractHandler makeCreateHandler({String tenantId = 'org-1'}) {
    final mockAuth = _MockAuthRepo();
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

  Future<String> createSource({String orgId = 'org-1'}) async {
    createHandler = makeCreateHandler(tenantId: orgId);
    final source = await createHandler.handle(
      CreateContractCommand(
        organizationId: orgId,
        name: 'Contrato Original',
        contractorName: 'Trans Norte Ltda',
        description: 'Descrição original',
        validFromUtc: validFrom,
        validUntilUtc: validUntil,
        sessionId: 'session-clone-src',
      ),
    );
    return source.id;
  }

  setUp(() {
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    final mockAuth = _MockAuthRepo();
    when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
      (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-1'),
    );
    final tvs = TenantValidationService(authRepository: mockAuth);
    cloneHandler = CloneContractHandler(
      tenantValidator: tvs,
      contractRepository: repository,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
    );
  });

  group('CloneContractHandler', () {
    test('clones a contract with new validity dates', () async {
      final sourceId = await createSource();

      final cloned = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          sourceContractId: sourceId,
          name: 'Contrato Clonado',
          contractorName: 'Trans Norte Ltda',
          description: 'Descrição clonada',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      expect(cloned.status, ContractStatus.draft);
      expect(cloned.id, isNot(equals(sourceId)));
      expect(cloned.name, 'Contrato Clonado');
      expect(cloned.contractorName, 'Trans Norte Ltda');
    });

    test('throws DomainException when source contract not found', () async {
      expect(
        () => cloneHandler.handle(
          const CloneContractCommand(
            organizationId: 'org-1',
            sessionId: 'session-1',
            sourceContractId: 'non-existent',
            name: 'Clone',
            contractorName: 'Contractor',
          ),
          validFromUtc: cloneFrom,
          validUntilUtc: cloneUntil,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'throws SovereigntyViolationException for wrong organization (tenant isolation)',
      () async {
        final sourceId = await createSource(orgId: 'org-A');

        expect(
          () => cloneHandler.handle(
            CloneContractCommand(
              organizationId: 'org-B',
              sessionId: 'session-1',
              sourceContractId: sourceId,
              name: 'Clone',
              contractorName: 'Contractor',
            ),
            validFromUtc: cloneFrom,
            validUntilUtc: cloneUntil,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test('throws DomainException for empty name', () async {
      final sourceId = await createSource();

      expect(
        () => cloneHandler.handle(
          CloneContractCommand(
            organizationId: 'org-1',
            sessionId: 'session-1',
            sourceContractId: sourceId,
            name: '',
            contractorName: 'Contractor',
          ),
          validFromUtc: cloneFrom,
          validUntilUtc: cloneUntil,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('appends CONTRACT_CREATED event to ledger for the clone', () async {
      final sourceId = await createSource();

      await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          sourceContractId: sourceId,
          name: 'Cloned',
          contractorName: 'Contractor',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      // Source created + Clone created
      expect(ledger.entries, hasLength(2));
      expect(ledger.entries.last.type, 'CONTRACT_CREATED');
    });

    test('creates clone with distinct ID from source', () async {
      final sourceId = await createSource();

      final cloned = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          sourceContractId: sourceId,
          name: 'Cloned',
          contractorName: 'Contractor',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      expect(cloned.id, isNot(equals(sourceId)));
      expect(cloned.status, ContractStatus.draft);
    });
  });
}
