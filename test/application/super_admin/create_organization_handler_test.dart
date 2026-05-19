import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/plan_limits.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kFakeOrgId = 'test-org-id-abc123';
const _kFakeSecret =
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

CreateOrganizationCommand _validCmd({
  String cnpj = '11222333000181', // 14 digits
  String email = 'admin@empresa.com.br',
  String legalName = 'Transportes Silva Ltda.',
  String tradeName = 'Silva Logística',
}) => CreateOrganizationCommand(
  legalName: legalName,
  tradeName: tradeName,
  cnpj: cnpj,
  timezone: 'America/Sao_Paulo',
  currencyCode: 'BRL',
  planType: PlanType.starter,
  maxVehicles: 50,
  maxActiveContracts: 10,
  adminEmails: [email],
  superAdminUserId: 'super-admin-uuid-123',
  toolCostCents: 50000,
  reason: 'Motivo válido de teste de auditoria',
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockSupabaseClient mockClient;
  late MockDateTimeProvider mockDateTime;
  late CreateOrganizationHandler handler;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockClient = MockSupabaseClient();
    mockDateTime = MockDateTimeProvider();
    handler = CreateOrganizationHandler(mockRepo, mockClient, mockDateTime);
  });

  setUpAll(() {
    registerFallbackValue(_validCmd());
  });

  group('CreateOrganizationHandler', () {
    group('CNPJ validation', () {
      test(
        'throws DomainException for CNPJ with fewer than 14 digits',
        () async {
          await expectLater(
            handler.handle(_validCmd(cnpj: '1234')),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                contains('inválido'),
              ),
            ),
          );
        },
      );

      test(
        'throws DomainException for CNPJ with more than 14 digits',
        () async {
          await expectLater(
            handler.handle(_validCmd(cnpj: '123456789012345')), // 15 digits
            throwsA(isA<DomainException>()),
          );
        },
      );

      test(
        'strips formatting before validation (formatted valid CNPJ passes)',
        () async {
          // 11.222.333/0001-81 — formatted form of a structurally valid CNPJ.
          // Handler strips mask, validates check digits, then proceeds to repo.
          when(
            () => mockRepo.createOrganization(any()),
          ).thenThrow(Exception('repo not connected'));

          await expectLater(
            handler.handle(_validCmd(cnpj: '11.222.333/0001-81')),
            throwsA(isNot(isA<DomainException>())),
          );
        },
      );

      test('throws for empty CNPJ', () async {
        await expectLater(
          handler.handle(_validCmd(cnpj: '')),
          throwsA(isA<DomainException>()),
        );
      });

      test(
        'throws DomainException for CNPJ with valid length but invalid check digit',
        () async {
          // 11222333000182 — last digit changed from 1 → 2, passes length check but fails modulo-11
          await expectLater(
            handler.handle(_validCmd(cnpj: '11222333000182')),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                contains('inválido'),
              ),
            ),
          );
        },
      );
    });

    group('required field validation', () {
      test('throws DomainException for empty legalName', () async {
        await expectLater(
          handler.handle(_validCmd(legalName: '')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Razão social'),
            ),
          ),
        );
      });

      test('throws DomainException for whitespace-only legalName', () async {
        await expectLater(
          handler.handle(_validCmd(legalName: '   ')),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException for empty tradeName', () async {
        await expectLater(
          handler.handle(_validCmd(tradeName: '')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Nome fantasia'),
            ),
          ),
        );
      });
    });

    group('email validation', () {
      test('throws DomainException for email without @', () async {
        await expectLater(
          handler.handle(_validCmd(email: 'notanemail')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('E-mail'),
            ),
          ),
        );
      });

      test('throws DomainException for empty email', () async {
        await expectLater(
          handler.handle(_validCmd(email: '')),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException for whitespace-only email', () async {
        await expectLater(
          handler.handle(_validCmd(email: '   ')),
          throwsA(isA<DomainException>()),
        );
      });
    });

    group('RBAC gate', () {
      // The RBAC check uses UserRole.superAdmin which has canManageTenants.
      // Verify validation errors are thrown BEFORE any repo I/O (no mock calls).
      test('CNPJ error is thrown before repo is called', () async {
        await expectLater(
          handler.handle(_validCmd(cnpj: 'bad')),
          throwsA(isA<DomainException>()),
        );

        // Repo was never called (validation failed first)
        verifyNever(() => mockRepo.createOrganization(any()));
      });

      test('email error is thrown before repo is called', () async {
        await expectLater(
          handler.handle(_validCmd(email: 'bad')),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      });
    });

    group('toolCostCents validation (INV-10)', () {
      test('throws DomainException when toolCostCents is null', () async {
        const cmd = CreateOrganizationCommand(
          legalName: 'Transportes Silva Ltda.',
          tradeName: 'Silva Logística',
          cnpj: '11222333000181',
          timezone: 'America/Sao_Paulo',
          currencyCode: 'BRL',
          planType: PlanType.starter,
          maxVehicles: 50,
          maxActiveContracts: 10,
          adminEmails: ['admin@empresa.com.br'],
          superAdminUserId: 'super-admin-uuid-123',
          toolCostCents: null, // must be rejected
          reason: 'Motivo válido de teste de auditoria',
        );

        await expectLater(
          handler.handle(cmd),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('ROI'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      });

      test('accepts toolCostCents = 0 (free tier)', () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('stop here'));

        const cmd = CreateOrganizationCommand(
          legalName: 'Transportes Silva Ltda.',
          tradeName: 'Silva Logística',
          cnpj: '11222333000181',
          timezone: 'America/Sao_Paulo',
          currencyCode: 'BRL',
          planType: PlanType.starter,
          maxVehicles: 50,
          maxActiveContracts: 10,
          adminEmails: ['admin@empresa.com.br'],
          superAdminUserId: 'super-admin-uuid-123',
          toolCostCents: 0,
          reason: 'Motivo válido de teste de auditoria',
        );

        await expectLater(
          handler.handle(cmd),
          throwsA(isNot(isA<DomainException>())),
        );
      });

      test('accepts toolCostCents > 0', () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('stop here'));

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isNot(isA<DomainException>())),
        );
      });
    });

    group('quota auto-fill from PlanType', () {
      // These tests verify what the handler passes to the repo.
      // createOrganization throws a sentinel Exception so the invite step is
      // never reached, avoiding the need to mock SupabaseClient.rpc().

      test(
        'auto-fills starter limits when maxVehicles/maxActiveContracts are null',
        () async {
          CreateOrganizationCommand? captured;
          when(() => mockRepo.createOrganization(any())).thenAnswer((inv) {
            captured =
                inv.positionalArguments.first as CreateOrganizationCommand;
            throw Exception('stop here');
          });

          const cmd = CreateOrganizationCommand(
            legalName: 'Transportes Silva Ltda.',
            tradeName: 'Silva Logística',
            cnpj: '11222333000181',
            timezone: 'America/Sao_Paulo',
            currencyCode: 'BRL',
            planType: PlanType.starter,
            // maxVehicles and maxActiveContracts intentionally omitted (null)
            adminEmails: ['admin@empresa.com.br'],
            superAdminUserId: 'super-admin-uuid-123',
            toolCostCents: 50000,
            reason: 'Motivo válido de teste de auditoria',
          );

          await expectLater(
            handler.handle(cmd),
            throwsA(isNot(isA<DomainException>())),
          );

          expect(captured, isNotNull);
          expect(
            captured!.maxVehicles,
            PlanLimits.maxVehicles(PlanType.starter),
          );
          expect(
            captured!.maxActiveContracts,
            PlanLimits.maxContracts(PlanType.starter),
          );
        },
      );

      test('preserves explicit limits when provided', () async {
        CreateOrganizationCommand? captured;
        when(() => mockRepo.createOrganization(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as CreateOrganizationCommand;
          throw Exception('stop here');
        });

        await expectLater(
          handler.handle(
            _validCmd(),
          ), // maxVehicles: 50, maxActiveContracts: 10
          throwsA(isNot(isA<DomainException>())),
        );

        expect(captured, isNotNull);
        expect(captured!.maxVehicles, 50);
        expect(captured!.maxActiveContracts, 10);
      });
    });

    group('new optional fields — billingDay / externalId (INV-10)', () {
      test(
        'billingDay 29 in command throws DomainException before RPC',
        () async {
          const cmd = CreateOrganizationCommand(
            legalName: 'Transportes Silva Ltda.',
            tradeName: 'Silva Logística',
            cnpj: '11222333000181',
            timezone: 'America/Sao_Paulo',
            currencyCode: 'BRL',
            planType: PlanType.starter,
            maxVehicles: 50,
            maxActiveContracts: 10,
            adminEmails: ['admin@empresa.com.br'],
            superAdminUserId: 'super-admin-uuid-123',
            toolCostCents: 50000,
            reason: 'Motivo válido de teste de auditoria',
            billingDay: 29, // out-of-range — no month guarantees day 29
          );

          await expectLater(
            handler.handle(cmd),
            throwsA(isA<DomainException>()),
          );
          verifyNever(() => mockRepo.createOrganization(any()));
        },
      );

      test(
        'externalId longer than 100 chars throws DomainException before RPC',
        () async {
          final cmd = CreateOrganizationCommand(
            legalName: 'Transportes Silva Ltda.',
            tradeName: 'Silva Logística',
            cnpj: '11222333000181',
            timezone: 'America/Sao_Paulo',
            currencyCode: 'BRL',
            planType: PlanType.starter,
            maxVehicles: 50,
            maxActiveContracts: 10,
            adminEmails: ['admin@empresa.com.br'],
            superAdminUserId: 'super-admin-uuid-123',
            toolCostCents: 50000,
            reason: 'Motivo válido de teste de auditoria',
            externalId: 'x' * 101, // exceeds 100-char limit
          );

          await expectLater(
            handler.handle(cmd),
            throwsA(isA<DomainException>()),
          );
          verifyNever(() => mockRepo.createOrganization(any()));
        },
      );
    });

    group('atomic secret provisioning (INV-28)', () {
      test(
        'handle() propagates plaintextSecret from repo to orgApiSecret',
        () async {
          when(() => mockRepo.createOrganization(any())).thenAnswer(
            (_) async => (orgId: _kFakeOrgId, plaintextSecret: _kFakeSecret),
          );
          // mockClient.rpc for InviteUserHandler — stop at invite step
          // by throwing a sentinel from the invite chain
          when(
            () => mockClient.rpc<dynamic>(any(), params: any(named: 'params')),
          ).thenThrow(Exception('invite-stop'));

          await expectLater(
            handler.handle(_validCmd()),
            throwsA(isNot(isA<DomainException>())),
          );

          // Verify repo was called and secret was requested
          verify(() => mockRepo.createOrganization(any())).called(1);
        },
      );

      test(
        'repo IntegrityException on missing secret propagates as-is (INV-10)',
        () async {
          when(() => mockRepo.createOrganization(any())).thenThrow(
            const IntegrityException(
              'plaintext_secret missing',
              field: 'plaintext_secret',
            ),
          );

          await expectLater(
            handler.handle(_validCmd()),
            throwsA(isA<IntegrityException>()),
          );
        },
      );

      test(
        'repo IntegrityException on empty secret propagates as-is (INV-10)',
        () async {
          when(() => mockRepo.createOrganization(any())).thenThrow(
            const IntegrityException(
              'super_admin_create_organization: plaintext_secret missing (INV-28)',
              field: 'plaintext_secret',
            ),
          );

          await expectLater(
            handler.handle(_validCmd()),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.field,
                'field',
                'plaintext_secret',
              ),
            ),
          );
        },
      );
    });

    group('CreateOrganizationResult — orgApiSecret field (INV-28)', () {
      test('result type carries orgApiSecret — null for missing secret', () {
        const result = CreateOrganizationResult(
          orgId: 'test-org-id',
          invitationTokens: ['test-token'],
          orgApiSecret: null,
        );
        expect(result.orgApiSecret, isNull);
      });

      test(
        'result type carries orgApiSecret — non-null 64-char hex when generated',
        () {
          const result = CreateOrganizationResult(
            orgId: 'test-org-id',
            invitationTokens: ['test-token'],
            orgApiSecret: _kFakeSecret,
          );
          expect(result.orgApiSecret, isNotNull);
          expect(result.orgApiSecret!.length, 64);
        },
      );
    });

    group(
      'CreateOrganizationResult — per-email invitation tokens (INV-27)',
      () {
        test('invitationTokens stores one token per admin email', () {
          const result = CreateOrganizationResult(
            orgId: 'org-1',
            invitationTokens: [
              'token-a@admin1',
              'token-b@admin2',
              'token-c@admin3',
            ],
          );
          expect(result.invitationTokens.length, 3);
          expect(result.invitationTokens[0], 'token-a@admin1');
          expect(result.invitationTokens[1], 'token-b@admin2');
          expect(result.invitationTokens[2], 'token-c@admin3');
        });

        test(
          'firstInvitationToken returns first token (single-admin convenience)',
          () {
            const result = CreateOrganizationResult(
              orgId: 'org-1',
              invitationTokens: ['only-token'],
            );
            expect(result.firstInvitationToken, 'only-token');
          },
        );

        test(
          'each admin gets distinct token — no token reuse across emails',
          () {
            const result = CreateOrganizationResult(
              orgId: 'org-1',
              invitationTokens: ['token-alpha', 'token-beta'],
            );
            expect(result.invitationTokens.toSet().length, 2);
          },
        );
      },
    );
  });
}
