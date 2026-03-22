import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

// ── Helpers ───────────────────────────────────────────────────────────────────

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
  planType: 'starter',
  maxVehicles: 50,
  maxActiveContracts: 10,
  initialAdminEmail: email,
  superAdminUserId: 'super-admin-uuid-123',
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockSupabaseClient mockClient;
  late CreateOrganizationHandler handler;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockClient = MockSupabaseClient();
    handler = CreateOrganizationHandler(mockRepo, mockClient);
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
                contains('14 dígitos'),
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
        'strips formatting before counting (00.000.000/0001-99 has 14 digits)',
        () async {
          // The handler should NOT throw for a formatted CNPJ with 14 underlying digits.
          // It will proceed to the repo call — we verify no DomainException is thrown
          // for the CNPJ itself (the subsequent repo call will throw, which is fine).
          when(
            () => mockRepo.createOrganization(any()),
          ).thenThrow(Exception('repo not connected'));

          await expectLater(
            handler.handle(_validCmd(cnpj: '00.000.000/0001-99')),
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
  });
}
