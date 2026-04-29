import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/application/super_admin/archive_organization_handler.dart';
import 'package:veraprob/domain/super_admin/archive_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

ArchiveOrganizationCommand _validCmd({
  String orgId = 'org-uuid-abc123',
  String reason = 'Organização inativa há mais de 12 meses',
  String superAdminUserId = 'super-admin-uuid-123',
  OrgStatus currentStatus = OrgStatus.active,
  String sessionId = 'session-uuid-123',
}) => ArchiveOrganizationCommand(
  orgId: orgId,
  reason: reason,
  superAdminUserId: superAdminUserId,
  currentStatus: currentStatus,
  sessionId: sessionId,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late ArchiveOrganizationHandler handler;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    handler = ArchiveOrganizationHandler(
      repository: mockRepo,
      tenantValidator: const SuperAdminBypassTenantValidator(),
    );
  });

  setUpAll(() {
    registerFallbackValue(_validCmd());
  });

  group('ArchiveOrganizationHandler', () {
    group('happy path', () {
      test('active org → calls archiveOrganization on repo', () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd());

        verify(() => mockRepo.archiveOrganization(any())).called(1);
      });

      test('trial org → calls archiveOrganization on repo', () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd(currentStatus: OrgStatus.trial));

        verify(() => mockRepo.archiveOrganization(any())).called(1);
      });
    });

    group('reason validation (INV-10)', () {
      test('empty reason throws DomainException', () async {
        await expectLater(
          handler.handle(_validCmd(reason: '')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('motivo'),
            ),
          ),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });

      test('whitespace-only reason throws DomainException', () async {
        await expectLater(
          handler.handle(_validCmd(reason: '   ')),
          throwsA(isA<DomainException>()),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });

      test('reason shorter than 10 chars throws DomainException', () async {
        await expectLater(
          handler.handle(_validCmd(reason: 'Inativo')),
          throwsA(isA<DomainException>()),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });

      test('reason exactly 10 chars passes', () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd(reason: '1234567890'));

        verify(() => mockRepo.archiveOrganization(any())).called(1);
      });
    });

    group('status guard (INV-26)', () {
      test(
        'already-archived org throws DomainException — idempotency guard',
        () async {
          await expectLater(
            handler.handle(_validCmd(currentStatus: OrgStatus.archived)),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                contains('arquivada'),
              ),
            ),
          );
          verifyNever(() => mockRepo.archiveOrganization(any()));
        },
      );

      test('deleted org throws DomainException — INV-26 parity', () async {
        await expectLater(
          handler.handle(_validCmd(currentStatus: OrgStatus.deleted)),
          throwsA(isA<DomainException>()),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });
    });

    group('validation order', () {
      test('status guard fires before repo call', () async {
        await expectLater(
          handler.handle(_validCmd(currentStatus: OrgStatus.archived)),
          throwsA(isA<DomainException>()),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });

      test('reason guard fires before repo call', () async {
        await expectLater(
          handler.handle(_validCmd(reason: '')),
          throwsA(isA<DomainException>()),
        );
        verifyNever(() => mockRepo.archiveOrganization(any()));
      });
    });
  });
}
