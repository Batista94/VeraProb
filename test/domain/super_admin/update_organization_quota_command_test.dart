import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockSystemAuditLogService extends Mock implements SystemAuditLogService {}

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
  late MockSystemAuditLogService mockAudit;
  late MockTenantValidationService mockValidator;
  late UpdateOrganizationQuotaHandler handler;

  setUpAll(() {
    registerFallbackValue(_cmd());
    registerFallbackValue(ActorType.human);
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockAudit = MockSystemAuditLogService();
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
      auditLogService: mockAudit,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY
  // ══════════════════════════════════════════════════════════════════════════

  group('CONFIDENTIALITY', () {
    test(
      'unauthorized session — validator throws, repo and audit never called',
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
        verifyNever(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
        );
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
        verifyNever(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
        );
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
        when(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
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

    test('audit log fired with correct snapshot after happy path', () async {
      String? capturedEventType;
      String? capturedOrgId;
      Map<String, Object?>? capturedNewSnapshot;

      when(
        () => mockRepo.updateOrganizationQuota(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockAudit.logGovernanceChange(
          eventType: any(named: 'eventType'),
          reason: any(named: 'reason'),
          actorType: any(named: 'actorType'),
          organizationId: any(named: 'organizationId'),
          oldSnapshot: any(named: 'oldSnapshot'),
          newSnapshot: any(named: 'newSnapshot'),
        ),
      ).thenAnswer((invocation) async {
        capturedEventType =
            invocation.namedArguments[const Symbol('eventType')] as String?;
        capturedOrgId =
            invocation.namedArguments[const Symbol('organizationId')]
                as String?;
        capturedNewSnapshot =
            invocation.namedArguments[const Symbol('newSnapshot')]
                as Map<String, Object?>?;
      });

      await handler.handle(
        _cmd(
          organizationId: 'org-audit-verify',
          newPlanType: 'enterprise',
          newMaxVehicles: 200,
          toolCostCents: 99900,
        ),
      );

      verify(
        () => mockAudit.logGovernanceChange(
          eventType: any(named: 'eventType'),
          reason: any(named: 'reason'),
          actorType: any(named: 'actorType'),
          organizationId: any(named: 'organizationId'),
          oldSnapshot: any(named: 'oldSnapshot'),
          newSnapshot: any(named: 'newSnapshot'),
        ),
      ).called(1);

      expect(capturedEventType, 'QUOTA_CHANGE');
      expect(capturedOrgId, 'org-audit-verify');
      expect(capturedNewSnapshot!['plan_type'], 'enterprise');
      expect(capturedNewSnapshot!['max_vehicles'], 200);
      expect(capturedNewSnapshot!['tool_cost_cents'], 99900);
    });

    test(
      'atomicity: repo failure — audit logGovernanceChange NEVER called',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenThrow(Exception('db_failure'));

        await expectLater(handler.handle(_cmd()), throwsA(isA<Exception>()));

        verifyNever(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
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
      'upgrade path professional→enterprise with null limits — completes, audit called once',
      () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        when(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
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

        verify(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
        ).called(1);
      },
    );

    test(
      'OCC collision — P0001 rethrown as DomainException, audit never called',
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

        verifyNever(
          () => mockAudit.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            organizationId: any(named: 'organizationId'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
        );
      },
    );

    test(
      'no audit service wired — null auditLogService, repo succeeds, completes without NPE',
      () async {
        final handlerNoAudit = UpdateOrganizationQuotaHandler(
          tenantValidator: mockValidator,
          repository: mockRepo,
        );

        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await expectLater(handlerNoAudit.handle(_cmd()), completes);
      },
    );
  });
}
