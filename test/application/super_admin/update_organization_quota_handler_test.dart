import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

UpdateOrganizationQuotaCommand _validCmd({
  String organizationId = 'org-uuid-123',
  String newPlanType = 'professional',
  int? newMaxVehicles = 100,
  int? newMaxActiveContracts = 50,
  String superAdminUserId = 'super-admin-uuid-456',
  String? reason = 'Ajuste de cota conforme contrato atualizado',
  String sessionId = 'session-uuid-789',
  int? toolCostCents = 50000,
  String? tradeName,
  String? legalName,
}) => UpdateOrganizationQuotaCommand(
  organizationId: organizationId,
  newPlanType: newPlanType,
  newMaxVehicles: newMaxVehicles,
  newMaxActiveContracts: newMaxActiveContracts,
  superAdminUserId: superAdminUserId,
  reason: reason,
  sessionId: sessionId,
  toolCostCents: toolCostCents,
  tradeName: tradeName,
  legalName: legalName,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late UpdateOrganizationQuotaHandler handler;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    handler = UpdateOrganizationQuotaHandler(
      repository: mockRepo,
      tenantValidator: const SuperAdminBypassTenantValidator(),
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

    group('toolCostCents validation (INV-10)', () {
      test('throws DomainException when toolCostCents is null', () async {
        await expectLater(
          handler.handle(_validCmd(toolCostCents: null)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('ROI'),
            ),
          ),
        );
        verifyNever(() => mockRepo.updateOrganizationQuota(any()));
      });

      test('accepts toolCostCents = 0', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(
          handler.handle(_validCmd(toolCostCents: 0)),
          completes,
        );
      });

      test('accepts positive toolCostCents', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});
        await expectLater(handler.handle(_validCmd()), completes);
      });
    });

    // ── Regression: bugs fixed in 20260706 ────────────────────────────────────
    // Bug 1 — double-write: handler was writing a second system_audit_log entry
    //   after CT11 already made the RPC the sole authoritative writer.
    // Bug 2 — name fields absent from audit payload: tradeName/legalName were
    //   never forwarded, so the DB diff was blind to cadastral changes.
    // These tests pin the handler contract so both bugs stay dead.

    group('regression: CT11 double-write prevention', () {
      test(
        'happy path — repo called exactly once, no other interactions',
        () async {
          when(
            () => mockRepo.updateOrganizationQuota(any()),
          ).thenAnswer((_) async {});

          await handler.handle(_validCmd());

          verify(() => mockRepo.updateOrganizationQuota(any())).called(1);
          verifyNoMoreInteractions(mockRepo);
        },
      );

      test('name-only change — repo still called exactly once', () async {
        when(
          () => mockRepo.updateOrganizationQuota(any()),
        ).thenAnswer((_) async {});

        await handler.handle(
          _validCmd(
            tradeName: 'Novo Nome Fantasia',
            legalName: 'Nova Razão Social LTDA',
          ),
        );

        verify(() => mockRepo.updateOrganizationQuota(any())).called(1);
        verifyNoMoreInteractions(mockRepo);
      });
    });

    group(
      'regression: name fields propagation to repo (CT11 audit payload diff)',
      () {
        test('tradeName and legalName reach repo command unchanged', () async {
          when(
            () => mockRepo.updateOrganizationQuota(any()),
          ).thenAnswer((_) async {});

          await handler.handle(
            _validCmd(
              tradeName: 'Transportes Rápidos SA',
              legalName: 'Transportes Rápidos Sociedade Anônima',
            ),
          );

          final captured =
              verify(
                    () => mockRepo.updateOrganizationQuota(captureAny()),
                  ).captured.single
                  as UpdateOrganizationQuotaCommand;

          expect(captured.tradeName, 'Transportes Rápidos SA');
          expect(captured.legalName, 'Transportes Rápidos Sociedade Anônima');
        });

        test(
          'null tradeName and legalName preserved as null — DB COALESCE keeps existing',
          () async {
            when(
              () => mockRepo.updateOrganizationQuota(any()),
            ).thenAnswer((_) async {});

            await handler.handle(_validCmd(tradeName: null, legalName: null));

            final captured =
                verify(
                      () => mockRepo.updateOrganizationQuota(captureAny()),
                    ).captured.single
                    as UpdateOrganizationQuotaCommand;

            expect(captured.tradeName, isNull);
            expect(captured.legalName, isNull);
          },
        );
      },
    );

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
  });
}
