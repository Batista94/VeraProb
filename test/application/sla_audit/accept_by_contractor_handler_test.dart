import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/accept_by_contractor_command.dart';
import 'package:veraprob/application/sla_audit/accept_by_contractor_handler.dart';
import 'package:veraprob/application/sla_audit/contract_approval_command_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import '../../mocks/fake_date_time_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockSlaAuditLedgerRepository extends Mock
    implements SlaAuditLedgerRepository {}

/// Fake for ContractApprovalCommandService — avoids mocktail incompatibility
/// with Dart record return types.
class _FakeApprovalService extends Fake
    implements ContractApprovalCommandService {
  int acceptCallCount = 0;
  String? lastToken;
  bool shouldThrow = false;

  @override
  Future<void> submitForApproval({
    required String contractId,
    required String organizationId,
    required String tokenId,
    required String token,
    required DateTime expiresAtUtc,
    int? expectedVersion,
  }) async {}

  @override
  Future<({String contractId, String organizationId})> acceptByContractor({
    required String token,
  }) async {
    if (shouldThrow) {
      throw Exception('Token not found, expired, or already used');
    }
    acceptCallCount++;
    lastToken = token;
    return (contractId: 'contract-1', organizationId: 'org-1');
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late _FakeApprovalService approvalService;
  late MockSlaAuditLedgerRepository ledger;
  late AcceptByContractorHandler handler;

  setUpAll(() {
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'TEST',
        contractId: 'contract-1',
        planVersion: 0,
        occurredAtUtc: DateTime.now().toUtc(),
        payload: {},
      ),
    );
  });

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    approvalService = _FakeApprovalService();
    ledger = MockSlaAuditLedgerRepository();
    handler = AcceptByContractorHandler(
      tenantValidator: tenantValidator,
      approvalService: approvalService,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 1, 1)),
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

  group('AcceptByContractorHandler', () {
    test('Token vazio — lança DomainException sem chamar o RPC', () async {
      await expectLater(
        () => handler.handle(const AcceptByContractorCommand(token: '')),
        throwsA(isA<DomainException>()),
      );
      expect(approvalService.acceptCallCount, 0);
      verifyNever(() => ledger.append(any()));
    });

    test('Token só espaços — lança DomainException sem chamar o RPC', () async {
      await expectLater(
        () => handler.handle(const AcceptByContractorCommand(token: '   ')),
        throwsA(isA<DomainException>()),
      );
      expect(approvalService.acceptCallCount, 0);
      verifyNever(() => ledger.append(any()));
    });

    test('Token válido — RPC chamado 1x, ledger appendado 1x', () async {
      const token = 'valid-token-uuid';

      await handler.handle(const AcceptByContractorCommand(token: token));

      expect(approvalService.acceptCallCount, 1);
      expect(approvalService.lastToken, token);
      verify(() => ledger.append(any())).called(1);
    });

    test('RPC lança (token expirado) — exceção propaga ao caller', () async {
      approvalService.shouldThrow = true;

      await expectLater(
        () => handler.handle(
          const AcceptByContractorCommand(token: 'expired-token'),
        ),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => ledger.append(any()));
    });
  });
}
