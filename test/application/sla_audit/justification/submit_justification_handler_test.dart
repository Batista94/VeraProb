import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_evidence.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockJustificationRepo extends Mock implements JustificationRepository {}

class MockLedgerRepo extends Mock implements SlaAuditLedgerRepository {}

class MockFactQueue extends Mock implements LocalFactQueueRepository {}

class MockRbac extends Mock implements RbacService {}

class MockClock extends Mock implements IDateTimeProvider {}

class MockAnalyzer extends Mock implements ContextualSignatureAnalyzer {}

class MockThrottle extends Mock implements ForensicThrottleGateway {}

class FakeJustification extends Fake implements ContractorJustification {}

class FakeEvidence extends Fake implements JustificationEvidence {}

class FakeLedgerEntry extends Fake implements SlaLedgerEntry {}

class FakePendingFact extends Fake implements PendingFact {}

void main() {
  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(UserPermission.canSubmitJustification);
    registerFallbackValue(FakeJustification());
    registerFallbackValue(FakeEvidence());
    registerFallbackValue(FakeLedgerEntry());
    registerFallbackValue(FakePendingFact());
  });

  group('SubmitJustificationHandler - INV-9 Evidence Sealing', () {
    late MockTenantValidator mockTenant;
    late MockJustificationRepo mockJustification;
    late MockLedgerRepo mockLedger;
    late MockFactQueue mockQueue;
    late MockRbac mockRbac;
    late MockClock mockClock;
    late MockAnalyzer mockAnalyzer;
    late MockThrottle mockThrottle;
    late SubmitJustificationHandler handler;

    final now = DateTime(2026, 4, 14, 18, 0).toUtc();

    setUp(() {
      mockTenant = MockTenantValidator();
      mockJustification = MockJustificationRepo();
      mockLedger = MockLedgerRepo();
      mockQueue = MockFactQueue();
      mockRbac = MockRbac();
      mockClock = MockClock();
      mockAnalyzer = MockAnalyzer();
      mockThrottle = MockThrottle();

      handler = SubmitJustificationHandler(
        tenantValidator: mockTenant,
        justificationRepo: mockJustification,
        ledger: mockLedger,
        factQueue: mockQueue,
        rbac: mockRbac,
        clock: mockClock,
        analyzer: mockAnalyzer,
        throttle: mockThrottle,
      );

      when(() => mockClock.nowUtc()).thenReturn(now);
      when(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockRbac.can(any(), any())).thenReturn(true);
      when(
        () => mockThrottle.assertAllowed(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockThrottle.recordFailure(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockThrottle.recordSuccess(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockAnalyzer.validateEvidence(any())).thenAnswer((_) async {});
      when(() => mockJustification.create(any())).thenAnswer(
        (_) async => ContractorJustification(
          id: 'just-1',
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          submittedByToken: null,
          category: JustificationCategory.mechanical,
          description: 'Test',
          status: JustificationStatus.pending,
          reviewedByUserId: null,
          reviewedAtUtc: null,
          createdAtUtc: now,
        ),
      );
      when(() => mockJustification.addEvidence(any())).thenAnswer(
        (_) async => JustificationEvidence(
          id: 'ev-1',
          justificationId: 'just-1',
          organizationId: 'org-1',
          fileName: 'test.pdf',
          contentHash: 'hash',
          storagePath: '/path',
          uploadedAtUtc: now,
        ),
      );
      when(() => mockLedger.append(any())).thenAnswer((_) async => 'entry-id');
      when(() => mockQueue.enqueue(any())).thenAnswer((_) async {});
    });

    test(
      'EDGE CASE: Rejects justification without cryptographic evidence',
      () async {
        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'MECHANICAL',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: [], // NO EVIDENCE
          evidenceUrls: [],
          callerUserId: 'user-1',
          callerEmail: 'user@example.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        // INV-9: Evidence is mandatory for forensic defensibility
        expect(
          () => handler.handle(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Evidence required'),
            ),
          ),
        );

        // Verify NO database writes occurred
        verifyNever(() => mockJustification.create(any()));
        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );

    test(
      'EDGE CASE: Accepts justification with valid SHA-256 evidence hash',
      () async {
        const validHash =
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'MECHANICAL',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: [validHash],
          evidenceUrls: ['https://signed.example/evidence-1'],
          callerUserId: 'user-1',
          callerEmail: 'user@example.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        final result = await handler.handle(command);

        expect(result.id, isNotEmpty);

        // Verify evidence was persisted with cryptographic seal
        verify(() => mockJustification.addEvidence(any())).called(1);
        verify(() => mockLedger.append(any())).called(1);
        verify(() => mockQueue.enqueue(any())).called(1);
      },
    );

    test('EDGE CASE: Invalid category throws DomainException', () async {
      const command = SubmitJustificationCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        category: 'invalid_category',
        description: 'Valid description with at least 20 characters',
        evidenceHashes: ['hash123'],
        evidenceUrls: ['https://signed.example/evidence-1'],
        callerUserId: 'user-1',
        callerEmail: 'user@example.com',
        callerRole: UserRole.operator,
        submittedByTokenId: null,
        planVersion: 1,
      );

      expect(
        () => handler.handle(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid justification category'),
          ),
        ),
      );

      verifyNever(() => mockJustification.create(any()));
      verifyNever(() => mockLedger.append(any()));
    });

    test('EDGE CASE: Description too short throws DomainException', () async {
      const command = SubmitJustificationCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        category: 'MECHANICAL',
        description: 'Too short', // Less than 20 chars
        evidenceHashes: ['hash123'],
        evidenceUrls: ['https://signed.example/evidence-1'],
        callerUserId: 'user-1',
        callerEmail: 'user@example.com',
        callerRole: UserRole.operator,
        submittedByTokenId: null,
        planVersion: 1,
      );

      expect(
        () => handler.handle(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('at least 20 characters'),
          ),
        ),
      );

      verifyNever(() => mockJustification.create(any()));
      verifyNever(() => mockLedger.append(any()));
    });

    test(
      'EDGE CASE: Token path bypasses RBAC but requires valid evidence',
      () async {
        when(() => mockRbac.can(any(), any())).thenReturn(false);

        const validHash =
            '123abc456def789012345678901234567890123456789012345678901234';

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'MECHANICAL',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: [validHash],
          evidenceUrls: ['https://signed.example/evidence-1'],
          callerUserId: null, // Token path
          callerEmail: null,
          callerRole: null, // Token path
          submittedByTokenId: 'token-123',
          planVersion: 1,
        );

        final result = await handler.handle(command);

        expect(result.submittedByToken, 'token-123');
        verify(() => mockJustification.create(any())).called(1);
        verify(() => mockLedger.append(any())).called(1);
      },
    );

    test(
      'CX-05-v3.0: ThrottleBlockedException short-circuits before persistence',
      () async {
        when(
          () => mockThrottle.assertAllowed(
            organizationId: any(named: 'organizationId'),
          ),
        ).thenThrow(const ThrottleBlockedException(8));

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'MECHANICAL',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: ['hash123'],
          evidenceUrls: ['https://signed.example/evidence-1'],
          callerUserId: 'user-1',
          callerEmail: 'user@example.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        await expectLater(
          handler.handle(command),
          throwsA(
            isA<ThrottleBlockedException>().having(
              (e) => e.waitSeconds,
              'waitSeconds',
              8,
            ),
          ),
        );

        verifyNever(() => mockAnalyzer.validateEvidence(any()));
        verifyNever(() => mockJustification.create(any()));
        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );

    test(
      'CX-05-v3.0: Analyzer failure records failure and rethrows, no persistence',
      () async {
        when(() => mockAnalyzer.validateEvidence(any())).thenThrow(
          const ForensicViolationException(
            message: 'Confirmed malicious signature',
            evidenceUrl: 'https://signed.example/evidence-1',
          ),
        );

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'MECHANICAL',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: ['hash123'],
          evidenceUrls: ['https://signed.example/evidence-1'],
          callerUserId: 'user-1',
          callerEmail: 'user@example.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        await expectLater(
          handler.handle(command),
          throwsA(isA<ForensicViolationException>()),
        );

        verify(
          () => mockThrottle.recordFailure(organizationId: 'org-1'),
        ).called(1);
        verifyNever(
          () => mockThrottle.recordSuccess(
            organizationId: any(named: 'organizationId'),
          ),
        );
        verifyNever(() => mockJustification.create(any()));
        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );

    test('CX-05-v3.0: Clean scan records success before persistence', () async {
      const validHash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const command = SubmitJustificationCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        category: 'MECHANICAL',
        description: 'Valid description with at least 20 characters',
        evidenceHashes: [validHash],
        evidenceUrls: ['https://signed.example/evidence-1'],
        callerUserId: 'user-1',
        callerEmail: 'user@example.com',
        callerRole: UserRole.operator,
        submittedByTokenId: null,
        planVersion: 1,
      );

      await handler.handle(command);

      verify(
        () => mockThrottle.assertAllowed(organizationId: 'org-1'),
      ).called(1);
      verify(() => mockAnalyzer.validateEvidence(any())).called(1);
      verify(
        () => mockThrottle.recordSuccess(organizationId: 'org-1'),
      ).called(1);
      verifyNever(
        () => mockThrottle.recordFailure(
          organizationId: any(named: 'organizationId'),
        ),
      );
      verify(() => mockJustification.create(any())).called(1);
      verify(() => mockLedger.append(any())).called(1);
      verify(() => mockQueue.enqueue(any())).called(1);
    });
  });
}
