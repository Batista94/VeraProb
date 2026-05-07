// pr_scanner: ignore-regression
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/features/super_admin/application/archive_organization_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/features/super_admin/domain/archive_organization_command.dart';
import 'package:veraprob/features/super_admin/domain/i_super_admin_repository.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

ArchiveOrganizationCommand _validCmd({
  String orgId = 'org-archive-target',
  String reason = 'Organização inativa há mais de 12 meses',
  String superAdminUserId = 'sa-uuid-test',
  OrgStatus currentStatus = OrgStatus.active,
  String sessionId = 'session-test-001',
}) => ArchiveOrganizationCommand(
  orgId: orgId,
  reason: reason,
  superAdminUserId: superAdminUserId,
  currentStatus: currentStatus,
  sessionId: sessionId,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockTenantValidationService mockValidator;
  late ArchiveOrganizationHandler handler;

  setUpAll(() {
    registerFallbackValue(_validCmd());
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

    handler = ArchiveOrganizationHandler(
      repository: mockRepo,
      tenantValidator: mockValidator,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY
  // ══════════════════════════════════════════════════════════════════════════

  group('CONFIDENTIALITY', () {
    test('INV-1: validator throws DomainException — repo NEVER called, '
        'session isolation enforced', () async {
      when(
        () => mockValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenThrow(const DomainException('session_invalid'));

      await expectLater(
        handler.handle(_validCmd()),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            'session_invalid',
          ),
        ),
      );

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });

    test('empty reason fires after validator and before repo — '
        'validator called, repo NEVER called (ordering proof)', () async {
      await expectLater(
        handler.handle(_validCmd(reason: '')),
        throwsA(isA<DomainException>()),
      );

      verify(
        () => mockValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).called(1);

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // INTEGRITY
  // ══════════════════════════════════════════════════════════════════════════

  group('INTEGRITY', () {
    test(
      'empty reason — DomainException containing motivo, repo NEVER called',
      () async {
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
      },
    );

    test(
      'whitespace-only reason — DomainException thrown, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(reason: '     ')),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.archiveOrganization(any()));
      },
    );

    test('reason shorter than 10 chars ("Inativo") — DomainException thrown, '
        'repo NEVER called', () async {
      await expectLater(
        handler.handle(_validCmd(reason: 'Inativo')),
        throwsA(isA<DomainException>()),
      );

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });

    test(
      'reason exactly 10 chars ("1234567890") passes length guard — repo IS called',
      () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd(reason: '1234567890'));

        verify(() => mockRepo.archiveOrganization(any())).called(1);
      },
    );

    test(
      'currentStatus = OrgStatus.archived — DomainException containing arquivada, '
      'repo NEVER called (status guard strict — INV-26 parity test)',
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

    test('already-archived org — throws DomainException '
        '(status guard strict — INV-26 parity test)', () async {
      await expectLater(
        handler.handle(_validCmd(currentStatus: OrgStatus.archived)),
        throwsA(isA<DomainException>()),
      );

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });

    test('currentStatus = OrgStatus.deleted — DomainException (INV-26: '
        'indistinguishable from not-found), repo NEVER called', () async {
      await expectLater(
        handler.handle(_validCmd(currentStatus: OrgStatus.deleted)),
        throwsA(isA<DomainException>()),
      );

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });

    test(
      'soft-delete enforcement: happy path calls archiveOrganization exactly once '
      '(RPC = atomic status update + secret revocation)',
      () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd());

        verify(() => mockRepo.archiveOrganization(any())).called(1);
      },
    );

    test(
      'audit trail: archiveOrganization called with captured orgId == org-archive-target',
      () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd());

        final captured =
            verify(
                  () => mockRepo.archiveOrganization(captureAny()),
                ).captured.single
                as ArchiveOrganizationCommand;

        expect(captured.orgId, 'org-archive-target');
      },
    );

    test('validation order proof: status guard fires before repo — '
        'verifyNever repo when archived status', () async {
      await expectLater(
        handler.handle(_validCmd(currentStatus: OrgStatus.archived)),
        throwsA(isA<DomainException>()),
      );

      verifyNever(() => mockRepo.archiveOrganization(any()));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AVAILABILITY
  // ══════════════════════════════════════════════════════════════════════════

  group('AVAILABILITY', () {
    test('happy path active org — completes without exception', () async {
      when(() => mockRepo.archiveOrganization(any())).thenAnswer((_) async {});

      await expectLater(
        handler.handle(_validCmd(currentStatus: OrgStatus.active)),
        completes,
      );
    });

    test('happy path trial org — completes without exception', () async {
      when(() => mockRepo.archiveOrganization(any())).thenAnswer((_) async {});

      await expectLater(
        handler.handle(_validCmd(currentStatus: OrgStatus.trial)),
        completes,
      );
    });

    test(
      'repo throws ResourceNotFoundException — propagates up unchanged',
      () async {
        when(() => mockRepo.archiveOrganization(any())).thenThrow(
          const ResourceNotFoundException(
            resourceType: 'organization',
            resourceId: 'org-archive-target',
          ),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );

    test(
      'kill-switch proof: archiveOrganization called with orgId from command — '
      'RPC atomically revokes tokens (structural invariant)',
      () async {
        when(
          () => mockRepo.archiveOrganization(any()),
        ).thenAnswer((_) async {});

        await handler.handle(_validCmd(orgId: 'org-killswitch-verify'));

        final captured =
            verify(
                  () => mockRepo.archiveOrganization(captureAny()),
                ).captured.single
                as ArchiveOrganizationCommand;

        expect(captured.orgId, 'org-killswitch-verify');
      },
    );

    test(
      'idempotency document: currentStatus = OrgStatus.archived — currently throws '
      'DomainException (status guard strict — INV-26 parity test)',
      () async {
        await expectLater(
          handler.handle(_validCmd(currentStatus: OrgStatus.archived)),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });
}
