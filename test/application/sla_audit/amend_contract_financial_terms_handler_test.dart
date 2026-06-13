import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/amend_contract_financial_terms_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/contract_financial_amendment.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/i_contract_financial_amendment_repository.dart';

class _FakeAmendmentRepository
    implements IContractFinancialAmendmentRepository {
  String? lastContractId;
  int? lastCeilingCents;
  int? lastBps;
  DateTime? lastEffectiveAtUtc;
  String? lastNotes;

  @override
  Future<void> amendContractFinancialTerms({
    required String contractId,
    int? financialCeilingCents,
    required int penaltyMultiplierBps,
    required DateTime effectiveAtUtc,
    String? notes,
  }) async {
    lastContractId = contractId;
    lastCeilingCents = financialCeilingCents;
    lastBps = penaltyMultiplierBps;
    lastEffectiveAtUtc = effectiveAtUtc;
    lastNotes = notes;
  }

  @override
  Future<List<ContractFinancialAmendment>> getAmendmentsForContract(
    String contractId,
  ) async => const [];
}

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late _FakeAmendmentRepository fakeRepo;
  late AmendContractFinancialTermsHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    fakeRepo = _FakeAmendmentRepository();
    handler = AmendContractFinancialTermsHandler(
      tenantValidator: TenantValidationService(authRepository: mockAuthRepo),
      repository: fakeRepo,
      rbac: RbacService(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  AmendContractFinancialTermsCommand cmd({
    UserRole role = UserRole.admin,
    DateTime? effectiveAtUtc,
    int bps = 15000,
    int? ceilingCents = 5000000,
  }) {
    return AmendContractFinancialTermsCommand(
      organizationId: 'org-1',
      contractId: 'contract-1',
      financialCeilingCents: ceilingCents,
      penaltyMultiplierBps: bps,
      effectiveAtUtc: effectiveAtUtc ?? DateTime.now().toUtc(),
      notes: 'Renegociacao anual',
      callerRole: role,
      sessionId: 'session-1',
    );
  }

  group('AmendContractFinancialTermsHandler', () {
    test('operator role is denied — canEditSlaRules is admin-only', () async {
      expect(
        () => handler.handle(cmd(role: UserRole.operator)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('canEditSlaRules'),
          ),
        ),
      );
      expect(fakeRepo.lastContractId, isNull);
    });

    test('INV-15 — retroactive effective date throws IntegrityException '
        'before reaching the repository', () async {
      final retroactive = DateTime.now().toUtc().subtract(
        const Duration(days: 2),
      );

      await expectLater(
        handler.handle(cmd(effectiveAtUtc: retroactive)),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('Anti-backdating'),
          ),
        ),
      );
      expect(fakeRepo.lastContractId, isNull);
    });

    test('admin amends terms — all fields forwarded (INV-4 bps INT)', () async {
      final effective = DateTime.now().toUtc();
      await handler.handle(cmd(effectiveAtUtc: effective));

      expect(fakeRepo.lastContractId, 'contract-1');
      expect(fakeRepo.lastCeilingCents, 5000000);
      expect(fakeRepo.lastBps, 15000);
      expect(fakeRepo.lastEffectiveAtUtc, effective);
      expect(fakeRepo.lastNotes, 'Renegociacao anual');
    });

    test('null ceiling (no cap) is a valid amendment', () async {
      await handler.handle(cmd(ceilingCents: null));
      expect(fakeRepo.lastCeilingCents, isNull);
      expect(fakeRepo.lastBps, 15000);
    });
  });
}
