import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

UpdateOrganizationQuotaCommand _validCmd({
  String organizationId = 'org-uuid-123',
  String newPlanType = 'professional',
  int? newMaxVehicles = 100,
  int? newMaxActiveContracts = 50,
  String superAdminUserId = 'super-admin-uuid-456',
  String? reason,
  String sessionId = 'session-uuid-789',
}) => UpdateOrganizationQuotaCommand(
  organizationId: organizationId,
  newPlanType: newPlanType,
  newMaxVehicles: newMaxVehicles,
  newMaxActiveContracts: newMaxActiveContracts,
  superAdminUserId: superAdminUserId,
  reason: reason,
  sessionId: sessionId,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockAuthRepository mockAuth;
  late TenantValidationService tenantValidator;
  late UpdateOrganizationQuotaHandler handler;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockAuth = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuth);
    handler = UpdateOrganizationQuotaHandler(
      tenantValidator: tenantValidator,
      repository: mockRepo,
    );

    // Default: session is valid and matches org
    when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'super-admin-uuid-456',
        tenantId: 'org-uuid-123',
      ),
    );
  });

  setUpAll(() {
    registerFallbackValue(_validCmd());
  });

  group('UpdateOrganizationQuotaHandler', () {
    group('plan type validation', () {
      test('throws DomainException for unknown plan type', () async {
        await expectLater(
          handler.handle(_validCmd(newPlanType: 'gold')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Tipo de plano inválido'),
            ),
          ),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('accepts starter plan', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(_validCmd(newPlanType: 'starter')),
          completes,
        );
      });

      test('accepts professional plan', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(_validCmd(newPlanType: 'professional')),
          completes,
        );
      });

      test('accepts enterprise plan with null limits', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(
            _validCmd(
              newPlanType: 'enterprise',
              newMaxVehicles: null,
              newMaxActiveContracts: null,
            ),
          ),
          completes,
        );
      });
    });

    group('limit validation', () {
      test('throws DomainException when maxVehicles is 0', () async {
        await expectLater(
          handler.handle(_validCmd(newMaxVehicles: 0)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('veículos'),
            ),
          ),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('throws DomainException when maxVehicles is negative', () async {
        await expectLater(
          handler.handle(_validCmd(newMaxVehicles: -5)),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when maxActiveContracts is 0', () async {
        await expectLater(
          handler.handle(_validCmd(newMaxActiveContracts: 0)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('contratos'),
            ),
          ),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('accepts null maxVehicles (unlimited — enterprise)', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(
            _validCmd(
              newPlanType: 'enterprise',
              newMaxVehicles: null,
              newMaxActiveContracts: null,
            ),
          ),
          completes,
        );
      });

      test('accepts maxVehicles = 1 (minimum positive)', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(_validCmd(newMaxVehicles: 1)),
          completes,
        );
      });
    });

    group('happy path', () {
      test('delegates to repository with correct command', () async {
        final cmd = _validCmd(
          organizationId: 'org-uuid-123',
          newPlanType: 'professional',
          newMaxVehicles: 200,
          newMaxActiveContracts: 80,
          superAdminUserId: 'admin-xyz',
          reason: 'Upgrade requested',
        );

        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(cmd);

        final captured =
            verify(
                  () => mockRepo.updateOrganizationQuota(captureAny()),
                ).captured.single
                as UpdateOrganizationQuotaCommand;

        expect(captured.organizationId, 'org-uuid-123');
        expect(captured.newPlanType, 'professional');
        expect(captured.newMaxVehicles, 200);
        expect(captured.newMaxActiveContracts, 80);
        expect(captured.superAdminUserId, 'admin-xyz');
        expect(captured.reason, 'Upgrade requested');
      });
    });

    group('P0001 passthrough', () {
      test('wraps P0001 PostgrestException as DomainException', () async {
        when(() => mockRepo.updateOrganizationQuota(any())).thenThrow(
          const PostgrestException(
            message: 'Cota de veículos atingida.',
            code: 'P0001',
          ),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'Cota de veículos atingida.',
            ),
          ),
        );
      });

      test('rethrows non-P0001 PostgrestException', () async {
        when(() => mockRepo.updateOrganizationQuota(any())).thenThrow(
          const PostgrestException(message: 'Connection error', code: '08000'),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isA<PostgrestException>()),
        );
      });
    });

    group('tenant validation (INV-1)', () {
      test('throws SovereigntyViolationException on org mismatch', () async {
        when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
          (_) async => const domain.AuthUser(
            id: 'super-admin-uuid-456',
            tenantId: 'org-different',
          ),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isA<SovereigntyViolationException>()),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('throws SovereigntyViolationException on null user', () async {
        when(
          () => mockAuth.getUserBySessionId(any<String>()),
        ).thenAnswer((_) async => null);

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isA<SovereigntyViolationException>()),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('proceeds when org matches JWT', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await expectLater(handler.handle(_validCmd()), completes);

        verify(() => mockRepo.updateOrganizationQuota(any())).called(1);
      });
    });
  });
}
