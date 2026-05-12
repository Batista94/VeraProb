import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

UpdateOrganizationQuotaCommand _cmd({
  String organizationId = 'org-cia-001',
  String newPlanType = 'professional',
  int? newMaxVehicles = 50,
  int? newMaxActiveContracts = 25,
  String superAdminUserId = 'sa-cia-uuid',
  String? reason = 'Ajuste contratual homologado em reunião',
  String sessionId = 'session-cia-001',
  int? toolCostCents = 29900,
  int? dwellTimeSeconds,
  int? billingDay,
  String? contactEmail,
  String? externalId,
  String? organizationType,
  String? tradeName,
  String? legalName,
  DateTime? expectedUpdatedAt,
}) => UpdateOrganizationQuotaCommand(
  organizationId: organizationId,
  newPlanType: newPlanType,
  newMaxVehicles: newMaxVehicles,
  newMaxActiveContracts: newMaxActiveContracts,
  superAdminUserId: superAdminUserId,
  reason: reason,
  sessionId: sessionId,
  toolCostCents: toolCostCents,
  dwellTimeSeconds: dwellTimeSeconds,
  billingDay: billingDay,
  contactEmail: contactEmail,
  externalId: externalId,
  organizationType: organizationType,
  tradeName: tradeName,
  legalName: legalName,
  expectedUpdatedAt: expectedUpdatedAt,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockTenantValidationService mockValidator;
  late UpdateOrganizationQuotaHandler handler;

  setUpAll(() {
    registerFallbackValue(_cmd());
  });

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockValidator = MockTenantValidationService();

    when(
      () => mockValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    handler = UpdateOrganizationQuotaHandler(
      tenantValidator: mockValidator,
      repository: mockRepo,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY
  // ══════════════════════════════════════════════════════════════════════════

  group('CONFIDENTIALITY', () {
    test(
      'unauthorized session — validator throws, repo never called',
      () async {
        when(
          () => mockValidator.assertTenantMatches(
            payloadOrgId: any(named: 'payloadOrgId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(const DomainException('session_invalid'));

        await expectLater(
          handler.handle(_cmd()),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'session_invalid',
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );

    test(
      'null reason — throws DomainException containing Justificativa obrigatória',
      () async {
        await expectLater(
          handler.handle(_cmd(reason: null)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Justificativa obrigatória'),
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );

    test(
      'reason shorter than 10 chars — throws DomainException containing 10 caracteres',
      () async {
        await expectLater(
          handler.handle(_cmd(reason: 'Curto')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('10 caracteres'),
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // INTEGRITY
  // ══════════════════════════════════════════════════════════════════════════

  group('INTEGRITY', () {
    test(
      'negative maxVehicles (-100) — throws DomainException containing veículos',
      () async {
        await expectLater(
          handler.handle(_cmd(newMaxVehicles: -100)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('veículos'),
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );

    test(
      'negative maxActiveContracts (-50) — throws DomainException containing contratos',
      () async {
        await expectLater(
          handler.handle(_cmd(newMaxActiveContracts: -50)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('contratos'),
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );

    test(
      'dwellTimeSeconds = 60 (< 300) — throws DomainException containing 300 segundos',
      () async {
        await expectLater(
          handler.handle(_cmd(dwellTimeSeconds: 60)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('300 segundos'),
            ),
          ),
        );

        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      },
    );

    test(
      'maxVehicles = 999999999 — handler defers to DB, repo IS called with that value',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_cmd(newMaxVehicles: 999999999));

        final captured =
            verify(
                  () => mockRepo.updateOrganizationQuota(captureAny()),
                ).captured.single
                as UpdateOrganizationQuotaCommand;

        expect(captured.newMaxVehicles, 999999999);
      },
    );

    test(
      'atomicity: repo failure — exception propagates, handler does not swallow it',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenThrow(Exception('db_failure'));

        await expectLater(handler.handle(_cmd()), throwsA(isA<Exception>()));
      },
    );

    test(
      'OCC collision — PostgrestException P0001 rethrown as DomainException',
      () async {
        when(() => mockRepo.updateOrganizationQuota(any())).thenThrow(
          const PostgrestException(
            message: 'Conflito de versão detectado.',
            code: 'P0001',
          ),
        );

        await expectLater(
          handler.handle(_cmd()),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'Conflito de versão detectado.',
            ),
          ),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AVAILABILITY
  // ══════════════════════════════════════════════════════════════════════════

  group('AVAILABILITY', () {
    test(
      'upgrade path professional→enterprise with null limits — completes',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await expectLater(
          handler.handle(
            _cmd(
              newPlanType: 'enterprise',
              newMaxVehicles: null,
              newMaxActiveContracts: null,
            ),
          ),
          completes,
        );

        verify(() => mockRepo.updateOrganizationQuota(any())).called(1);
      },
    );

    test(
      'name-only change (tradeName set, quota fields default) — repo called once',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_cmd(tradeName: 'Novo Nome Fantasia'));

        final captured =
            verify(
                  () => mockRepo.updateOrganizationQuota(captureAny()),
                ).captured.single
                as UpdateOrganizationQuotaCommand;

        expect(captured.tradeName, 'Novo Nome Fantasia');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // REGRESSION (bugs fixed 2026-07-06)
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Bug A — double-write: handler wrote a second system_audit_log entry after
  //   CT11 made the RPC the sole authoritative writer. Fixed by removing
  //   Step 6 from the handler.
  //
  // Bug B — name fields absent from RPC audit payload: tradeName/legalName
  //   were never forwarded by the handler, so the DB could not build a
  //   before/after diff for cadastral changes. Fixed in migration
  //   20260706000007 + ensuring fields flow through the command to the repo.
  //
  // Bug C — wrong event_type: all updates logged as QUOTA_CHANGE even when
  //   only names changed. Fixed in migration 20260706000007 with dynamic
  //   event_type selection. DB-level; validated via integration test.

  group('REGRESSION', () {
    test(
      'repo called exactly once per handle — no double-write (Bug A)',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_cmd());

        verify(() => mockRepo.updateOrganizationQuota(any())).called(1);
        verifyNoMoreInteractions(mockRepo);
      },
    );

    test('legalName flows to repo command unchanged (Bug B)', () async {
      when(
        () => mockRepo.updateOrganizationQuota(any()),
      ).thenAnswer((_) async {});

      await handler.handle(_cmd(legalName: 'Empresa Teste Razão Social LTDA'));

      final captured =
          verify(
                () => mockRepo.updateOrganizationQuota(captureAny()),
              ).captured.single
              as UpdateOrganizationQuotaCommand;

      expect(captured.legalName, 'Empresa Teste Razão Social LTDA');
    });

    test(
      'null tradeName and legalName pass as null — DB COALESCE preserves existing (Bug B)',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_cmd(tradeName: null, legalName: null));

        final captured =
            verify(
                  () => mockRepo.updateOrganizationQuota(captureAny()),
                ).captured.single
                as UpdateOrganizationQuotaCommand;

        expect(captured.tradeName, isNull);
        expect(captured.legalName, isNull);
      },
    );

    test(
      'both tradeName and legalName set — both reach repo unchanged (Bug B)',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(
          _cmd(
            tradeName: 'Logística Verde SA',
            legalName: 'Logística Verde Sociedade Anônima',
          ),
        );

        final captured =
            verify(
                  () => mockRepo.updateOrganizationQuota(captureAny()),
                ).captured.single
                as UpdateOrganizationQuotaCommand;

        expect(captured.tradeName, 'Logística Verde SA');
        expect(captured.legalName, 'Logística Verde Sociedade Anônima');
      },
    );
  });
}
