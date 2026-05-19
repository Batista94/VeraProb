import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

/// Fake repository that raises a Postgres P0001 on [save].
class _QuotaExceededContractRepository implements ContractRepository {
  @override
  Future<Contract> save(Contract contract) async {
    throw const PostgrestException(
      message: 'Cota de contratos ativos atingida para este tenant.',
      code: 'P0001',
    );
  }

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async => null;

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async => [];
}

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    handler = CreateContractHandler(
      tenantValidator: tenantValidator,
      contractRepository: repository,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
    );

    // Default: session is valid and matches org-1
    when(() => mockAuthRepo.getUserBySessionId(any<String>())).thenAnswer(
      (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-1'),
    );
  });

  CreateContractCommand makeCommand({
    String organizationId = 'org-1',
    String sessionId = 'session-default',
    String name = 'Contrato Norte',
    String contractorName = 'Trans Norte Ltda',
    String? description,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return CreateContractCommand(
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFrom ?? DateTime.utc(2026, 1, 1),
      validUntilUtc: validUntil ?? DateTime.utc(2026, 12, 31),
      sessionId: sessionId,
    );
  }

  group('CreateContractHandler', () {
    test(
      'happy path — aggregate created in draft, persisted, ledger updated',
      () async {
        final contract = await handler.handle(makeCommand());

        // Status is draft
        expect(contract.status, ContractStatus.draft);
        expect(contract.isDraft, isTrue);

        // Identity and fields preserved
        expect(contract.id, isNotEmpty);
        expect(contract.organizationId, 'org-1');
        expect(contract.name, 'Contrato Norte');
        expect(contract.contractorName, 'Trans Norte Ltda');

        // Persisted in repository
        final found = await repository.findById(
          contract.id,
          organizationId: 'org-1',
        );
        expect(found, isNotNull);
        expect(found!.id, contract.id);

        // One ledger entry: CONTRACT_CREATED
        expect(ledger.entries, hasLength(1));
        expect(ledger.entries.first.type, 'CONTRACT_CREATED');
      },
    );

    test('with optional description', () async {
      final contract = await handler.handle(
        makeCommand(description: 'Cobertura região norte'),
      );

      expect(contract.description, 'Cobertura região norte');
    });

    test('two contracts produce distinct IDs', () async {
      final c1 = await handler.handle(makeCommand(name: 'Alpha'));
      final c2 = await handler.handle(makeCommand(name: 'Beta'));

      expect(c1.id, isNot(equals(c2.id)));
      expect(ledger.entries, hasLength(2));
    });

    test('DomainException — nothing persisted on invalid input', () async {
      expect(
        () => handler.handle(makeCommand(name: '')),
        throwsA(isA<DomainException>()),
      );

      final all = await repository.findByOrganization('org-1');
      expect(all, isEmpty);
      expect(ledger.entries, isEmpty);
    });

    test('tenant isolation — findById returns null for wrong org', () async {
      // Stub session for org-A
      when(() => mockAuthRepo.getUserBySessionId(any<String>())).thenAnswer(
        (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-A'),
      );

      final contract = await handler.handle(
        makeCommand(organizationId: 'org-A'),
      );

      final found = await repository.findById(
        contract.id,
        organizationId: 'org-B',
      );
      expect(found, isNull);
    });

    test('findByOrganization — filters by status', () async {
      await handler.handle(makeCommand(name: 'C1'));
      await handler.handle(makeCommand(name: 'C2'));

      final drafts = await repository.findByOrganization(
        'org-1',
        status: ContractStatus.draft,
      );
      expect(drafts, hasLength(2));

      final active = await repository.findByOrganization(
        'org-1',
        status: ContractStatus.active,
      );
      expect(active, isEmpty);
    });
  });

  group('P0001 quota enforcement', () {
    late _QuotaExceededContractRepository quotaRepo;
    late InMemorySlaAuditLedgerRepository quotaLedger;
    late CreateContractHandler quotaHandler;

    setUp(() {
      final mockAuth = MockAuthRepository();
      when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
        (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-1'),
      );
      final tvs = TenantValidationService(authRepository: mockAuth);
      quotaRepo = _QuotaExceededContractRepository();
      quotaLedger = InMemorySlaAuditLedgerRepository();
      quotaHandler = CreateContractHandler(
        tenantValidator: tvs,
        contractRepository: quotaRepo,
        ledger: quotaLedger,
        clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
      );
    });

    test('wraps P0001 PostgrestException as DomainException', () async {
      await expectLater(
        quotaHandler.handle(makeCommand()),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Cota de contratos ativos'),
          ),
        ),
      );
    });

    test('ledger remains empty when quota is exceeded', () async {
      try {
        await quotaHandler.handle(makeCommand());
      } catch (_) {}
      expect(quotaLedger.entries, isEmpty);
    });
  });

  group('submitForm — UI-friendly wrapper', () {
    test(
      'happy path — returns ContractFormResult.success with contract ID',
      () async {
        final result = await handler.submitForm(makeCommand());

        expect(result.isSuccess, isTrue);
        expect(result.contractId, isNotEmpty);
        expect(result.errorMessage, isNull);
      },
    );

    test(
      'DomainException — returns ContractFormResult.failure with user message',
      () async {
        final result = await handler.submitForm(makeCommand(name: ''));

        expect(result.isFailure, isTrue);
        expect(result.contractId, isNull);
        expect(result.errorMessage, contains('name must not be empty'));
      },
    );

    test(
      'SovereigntyViolationException — returns ContractFormResult.failure with INV-26 generic message',
      () async {
        // Stub session to return a different tenant than the one in the command
        when(() => mockAuthRepo.getUserBySessionId(any<String>())).thenAnswer(
          (_) async => const domain.AuthUser(id: 'user-1', tenantId: 'org-B'),
        );

        final result = await handler.submitForm(makeCommand());

        expect(result.isFailure, isTrue);
        expect(result.contractId, isNull);
        // INV-26: Message must NOT leak forensic details (org IDs)
        expect(result.errorMessage, 'Contrato não encontrado.');
      },
    );

    test(
      'unexpected error — returns ContractFormResult.unknownError',
      () async {
        final bombRepo = _BombContractRepository();
        final bombHandler = CreateContractHandler(
          tenantValidator: tenantValidator,
          contractRepository: bombRepo,
          ledger: ledger,
          clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
        );

        final result = await bombHandler.submitForm(makeCommand());

        expect(result.isFailure, isTrue);
        expect(result.contractId, isNull);
        expect(result.errorMessage, 'Erro inesperado. Tente novamente.');
      },
    );
  });
}

/// Repository that throws an unexpected exception (not DomainException or
/// SovereigntyViolationException) to test the catch-all branch of submitForm.
class _BombContractRepository implements ContractRepository {
  @override
  Future<Contract> save(Contract contract) async {
    throw Exception('database on fire');
  }

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async => null;

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async => [];
}
