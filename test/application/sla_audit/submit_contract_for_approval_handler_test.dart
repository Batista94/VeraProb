import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/contract_approval_command_service.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_command.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import '../../mocks/fake_date_time_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockContractRepository extends Mock implements ContractRepository {}

class MockSlaAuditLedgerRepository extends Mock
    implements SlaAuditLedgerRepository {}

/// Fake for ContractApprovalCommandService — avoids mocktail incompatibility
/// with Dart record return types in acceptByContractor.
class _FakeApprovalService extends Fake
    implements ContractApprovalCommandService {
  int submitCallCount = 0;
  String? lastTokenId;
  String? lastToken;

  @override
  Future<void> submitForApproval({
    required String contractId,
    required String organizationId,
    required String tokenId,
    required String token,
    required DateTime expiresAtUtc,
  }) async {
    submitCallCount++;
    lastTokenId = tokenId;
    lastToken = token;
  }

  @override
  Future<({String contractId, String organizationId})> acceptByContractor({
    required String token,
  }) async {
    return (contractId: 'dummy', organizationId: 'dummy');
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Contract _makeContract({ContractStatus status = ContractStatus.draft}) {
  return Contract.reconstitute(
    id: 'contract-1',
    version: 1,
    organizationId: 'org-1',
    name: 'Contrato Teste',
    contractorName: 'Empresa ABC',
    validFromUtc: DateTime.utc(2026, 1, 1),
    validUntilUtc: DateTime.utc(2026, 12, 31),
    status: status,
    createdAtUtc: DateTime.utc(2026, 1, 1),
    penaltyMultiplierBps: 10000,
  );
}

SubmitContractForApprovalCommand makeCommand({
  UserRole callerRole = UserRole.admin,
  String contractId = 'contract-1',
}) {
  return SubmitContractForApprovalCommand(
    organizationId: 'org-1',
    contractId: contractId,
    callerUserId: 'user-admin-1',
    callerRole: callerRole,
    sessionId: 'session-1',
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────
void main() {
  final nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late MockContractRepository contractRepository;
  late _FakeApprovalService approvalService;
  late MockSlaAuditLedgerRepository ledger;
  late SubmitContractForApprovalHandler handler;
  late FakeDateTimeProvider clock;

  setUpAll(() {
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'TEST',
        contractId: 'contract-1',
        planVersion: 0,
        occurredAtUtc: nowUtc,
        payload: {},
      ),
    );
  });

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    contractRepository = MockContractRepository();
    approvalService = _FakeApprovalService();
    ledger = MockSlaAuditLedgerRepository();
    clock = FakeDateTimeProvider(nowUtc);
    handler = SubmitContractForApprovalHandler(
      tenantValidator: tenantValidator,
      contractRepository: contractRepository,
      approvalService: approvalService,
      ledger: ledger,
      rbac: RbacService(),
      clock: clock,
    );
    when(() => ledger.append(any())).thenAnswer((_) async => 'entry-id');
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  group('SubmitContractForApprovalHandler', () {
    test('Rejeita operator — não tem canApproveContractAcceptance', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.operator)),
        throwsA(isA<DomainException>()),
      );
      verifyNever(
        () => contractRepository.findById(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      );
      expect(approvalService.submitCallCount, 0);
    });

    test('Rejeita auditor — não tem canApproveContractAcceptance', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
      expect(approvalService.submitCallCount, 0);
    });

    test('Contrato não encontrado — lança DomainException', () async {
      when(
        () =>
            contractRepository.findById('contract-1', organizationId: 'org-1'),
      ).thenAnswer((_) async => null);

      await expectLater(
        () => handler.handle(makeCommand()),
        throwsA(isA<DomainException>()),
      );
      expect(approvalService.submitCallCount, 0);
    });

    test('Contrato active — domain guard lança DomainException', () async {
      when(
        () =>
            contractRepository.findById('contract-1', organizationId: 'org-1'),
      ).thenAnswer((_) async => _makeContract(status: ContractStatus.active));

      await expectLater(
        () => handler.handle(makeCommand()),
        throwsA(isA<DomainException>()),
      );
    });

    test('Contrato closed — domain guard lança DomainException', () async {
      when(
        () =>
            contractRepository.findById('contract-1', organizationId: 'org-1'),
      ).thenAnswer((_) async => _makeContract(status: ContractStatus.closed));

      await expectLater(
        () => handler.handle(makeCommand()),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'Contrato awaitingContractorAcceptance — domain guard lança DomainException',
      () async {
        when(
          () => contractRepository.findById(
            'contract-1',
            organizationId: 'org-1',
          ),
        ).thenAnswer(
          (_) async => _makeContract(
            status: ContractStatus.awaitingContractorAcceptance,
          ),
        );

        await expectLater(
          () => handler.handle(makeCommand()),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      'Admin + draft — retorna token não-vazio, RPC chamado 1x, ledger appendado 1x',
      () async {
        when(
          () => contractRepository.findById(
            'contract-1',
            organizationId: 'org-1',
          ),
        ).thenAnswer((_) async => _makeContract());

        final token = await handler.handle(makeCommand());

        expect(token, isNotEmpty);
        expect(approvalService.submitCallCount, 1);
        expect(approvalService.lastToken, equals(token));
        verify(() => ledger.append(any())).called(1);
      },
    );

    test('Duas invocações retornam tokens distintos (INV-7)', () async {
      when(
        () => contractRepository.findById(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => _makeContract());

      final token1 = await handler.handle(makeCommand());
      final token2 = await handler.handle(makeCommand());

      expect(token1, isNot(equals(token2)));
    });
  });
}
