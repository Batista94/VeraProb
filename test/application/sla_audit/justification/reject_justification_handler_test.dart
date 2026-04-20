import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/reject_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/review_justification_command.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockJustificationRepository extends Mock
    implements JustificationRepository {}

class MockSlaAuditLedgerRepository extends Mock
    implements SlaAuditLedgerRepository {}

class MockRbacService extends Mock implements RbacService {}

void main() {
  late RejectJustificationHandler handler;
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late MockJustificationRepository mockJustificationRepo;
  late MockSlaAuditLedgerRepository mockLedger;
  late MockRbacService mockRbac;

  setUpAll(() {
    registerFallbackValue(UserRole.admin);
    registerFallbackValue(UserPermission.canReviewJustifications);
    registerFallbackValue(JustificationStatus.pending);
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'TYPE',
        operatorId: 'op-1',
        contractId: 'con-1',
        planVersion: 1,
        occurredAtUtc: DateTime.now().toUtc(),
      ),
    );
  });

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    mockJustificationRepo = MockJustificationRepository();
    mockLedger = MockSlaAuditLedgerRepository();
    mockRbac = MockRbacService();

    handler = RejectJustificationHandler(
      tenantValidator: tenantValidator,
      justificationRepo: mockJustificationRepo,
      ledger: mockLedger,
      rbac: mockRbac,
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-456',
      ),
    );
  });

  const testCommand = RejectJustificationCommand(
    justificationId: 'just-123',
    organizationId: 'org-456',
    planVersion: 1,
    callerRole: UserRole.admin,
    callerUserId: 'user-789',
    callerEmail: 'admin@veraprob.com',
    rejectionNotes: 'Insufficient evidence provided for the delay.',
    sessionId: 'session-1',
  );

  final testJustification = ContractorJustification(
    id: 'just-123',
    organizationId: 'org-456',
    contractId: 'cont-777',
    setId: 'trip-999',
    submittedByToken: null,
    category: JustificationCategory.forceMajeure,
    description: 'Heavy rain blocked the road.',
    status: JustificationStatus.pending,
    reviewedByUserId: null,
    reviewedAtUtc: null,
    createdAtUtc: DateTime.now().toUtc(),
  );

  group('RejectJustificationHandler Compliance & Forensic Audit', () {
    test(
      '1. RBAC: Should fail if user lacks canReviewJustifications permission',
      () async {
        when(() => mockRbac.can(any(), any())).thenReturn(false);

        await expectLater(
          () => handler.handle(testCommand),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'Unauthorized.',
            ),
          ),
        );
      },
    );

    group('2. Zero-Tolerance Validation (Notes)', () {
      setUp(() {
        when(() => mockRbac.can(any(), any())).thenReturn(true);
        when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
          (_) async =>
              const domain.AuthUser(id: 'u1', email: 'e1', tenantId: 'o1'),
        );
      });

      test('Fail if rejection notes are too short (< 10 chars)', () async {
        const shortCommand = RejectJustificationCommand(
          justificationId: 'j1',
          organizationId: 'o1',
          planVersion: 1,
          callerRole: UserRole.admin,
          callerUserId: 'u1',
          callerEmail: 'e1',
          rejectionNotes: 'Too bad', // 7 chars
          sessionId: 'session-1',
        );

        expect(
          () => handler.handle(shortCommand),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'Rejection notes must be at least 10 characters.',
            ),
          ),
        );
      });

      test('Fail if rejection notes contain only whitespace', () async {
        const spaceCommand = RejectJustificationCommand(
          justificationId: 'j1',
          organizationId: 'o1',
          planVersion: 1,
          callerRole: UserRole.admin,
          callerUserId: 'u1',
          callerEmail: 'e1',
          rejectionNotes: '          ', // whitespace
          sessionId: 'session-1',
        );

        expect(
          () => handler.handle(spaceCommand),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'Rejection notes must be at least 10 characters.',
            ),
          ),
        );
      });
    });

    test(
      '3. Idempotency Guard: Fail if justification is already processed',
      () async {
        when(() => mockRbac.can(any(), any())).thenReturn(true);
        when(
          () => mockJustificationRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer(
          (_) async =>
              testJustification.copyWith(status: JustificationStatus.rejected),
        );

        expect(
          () => handler.handle(testCommand),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('is already REJECTED'),
            ),
          ),
        );
      },
    );

    test(
      '4. Forensic Integrity: Transition status and preserve "Smoking Gun" in Ledger',
      () async {
        // Arrange
        when(() => mockRbac.can(any(), any())).thenReturn(true);
        when(
          () => mockJustificationRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => testJustification);

        when(() => mockLedger.append(any())).thenAnswer((_) async => 'evt-123');
        when(
          () => mockJustificationRepo.updateStatus(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            status: any(named: 'status'),
            reviewedByUserId: any(named: 'reviewedByUserId'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
          ),
        ).thenAnswer(
          (_) async =>
              testJustification.copyWith(status: JustificationStatus.rejected),
        );

        // Act
        await handler.handle(testCommand);

        // Assert: Verify Ledger Entry (Preserving original evidence)
        final capturedLedgerEntry =
            verify(() => mockLedger.append(captureAny())).captured.single
                as SlaLedgerEntry;

        expect(capturedLedgerEntry.type, 'JUSTIFICATION_REJECTED');
        expect(
          capturedLedgerEntry.setId,
          testJustification.setId,
        ); // Preservation of 'Smoking Gun' setId
        expect(
          capturedLedgerEntry.contractId,
          testJustification.contractId,
        ); // Preservation of 'Smoking Gun' contractId
        expect(capturedLedgerEntry.operatorId, testCommand.callerUserId);
        expect(
          capturedLedgerEntry.payload['justification_id'],
          testCommand.justificationId,
        );
        expect(
          capturedLedgerEntry.payload['actor_email'],
          testCommand.callerEmail,
        );
        expect(
          capturedLedgerEntry.occurredAtUtc.isUtc,
          isTrue,
        ); // UTC Requirement (INV-9)

        // Assert: Verify Repository Record (Audit Proof)
        verify(
          () => mockJustificationRepo.updateStatus(
            id: testCommand.justificationId,
            organizationId: testCommand.organizationId,
            status: JustificationStatus.rejected,
            reviewedByUserId: testCommand.callerUserId,
            reviewedAtUtc: any(
              named: 'reviewedAtUtc',
              that: isA<DateTime>().having((d) => d.isUtc, 'isUtc', isTrue),
            ),
          ),
        ).called(1);
      },
    );

    test(
      '5. UTC Timestamping (INV-9): Ensure timestamps are strictly UTC',
      () async {
        when(() => mockRbac.can(any(), any())).thenReturn(true);
        when(
          () => mockJustificationRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => testJustification);
        when(() => mockLedger.append(any())).thenAnswer((_) async => 'evt-123');
        when(
          () => mockJustificationRepo.updateStatus(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            status: any(named: 'status'),
            reviewedByUserId: any(named: 'reviewedByUserId'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
          ),
        ).thenAnswer(
          (_) async =>
              testJustification.copyWith(status: JustificationStatus.rejected),
        );

        await handler.handle(testCommand);

        final capturedUpdate =
            verify(
                  () => mockJustificationRepo.updateStatus(
                    id: any(named: 'id'),
                    organizationId: any(named: 'organizationId'),
                    status: any(named: 'status'),
                    reviewedByUserId: any(named: 'reviewedByUserId'),
                    reviewedAtUtc: captureAny(named: 'reviewedAtUtc'),
                  ),
                ).captured.single
                as DateTime;

        expect(capturedUpdate.isUtc, isTrue);
      },
    );
  });
}
