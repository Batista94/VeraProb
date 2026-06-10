import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_command.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late RejectSanctionHandler handler;
  late FakeDateTimeProvider clock;
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;

  final evidence = VerdictEvidence.create(
    clauseRef: 'no-show-rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 6, 10, 0),
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry makePendingEntry({String orgId = 'org-1'}) {
    return SanctionReviewQueueEntry(
      id: 'entry-001',
      organizationId: orgId,
      ledgerEntryId: 'ledger-001',
      setId: 'set-1',
      contractId: 'contract-1',
      verdictEvidence: evidence,
      status: SanctionReviewStatus.pending,
      createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
    );
  }

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    clock = FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0));
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    handler = RejectSanctionHandler(
      tenantValidator: tenantValidator,
      queueRepo: queueRepo,
      reviewRepo: InMemorySanctionReviewCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
      ),
      rbac: RbacService(),
      clock: clock,
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  group('RBAC', () {
    test('throws DomainException for operator role', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          const RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'user-op',
            actorEmail: 'op@test.com',
            rejectionReason: 'GPS data was inconclusive.',
            callerRole: UserRole.operator,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Rejection reason validation', () {
    test('throws DomainException for reason shorter than 10 chars', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          const RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            rejectionReason: 'too short', // 9 chars
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for reason that is only whitespace', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          const RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            rejectionReason: '          ', // 10 spaces, trims to empty
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts reason with exactly 10 chars after trim', () async {
      await queueRepo.enqueue(makePendingEntry());

      await expectLater(
        handler.handle(
          const RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            rejectionReason: '  1234567890  ', // 10 non-whitespace chars
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        completes,
      );
    });
  });

  group('Idempotency (INV-24)', () {
    test('throws DomainException if already rejected', () async {
      await queueRepo.enqueue(
        SanctionReviewQueueEntry(
          id: 'entry-001',
          organizationId: 'org-1',
          ledgerEntryId: 'ledger-001',
          setId: 'set-1',
          contractId: 'contract-1',
          verdictEvidence: evidence,
          status: SanctionReviewStatus.rejected,
          createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
        ),
      );

      expect(
        () => handler.handle(
          const RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            rejectionReason: 'GPS data was inconclusive for this route.',
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Happy path', () {
    test('appends VERDICT_REFUSED to ledger with actor_email', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        const RejectSanctionCommand(
          queueEntryId: 'entry-001',
          rejectedByUserId: 'auditor-1',
          actorEmail: 'auditor@veraprob.com',
          rejectionReason: 'GPS data was inconclusive for this route.',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
      );

      final entries = ledger.entries;
      expect(entries.length, 1);
      expect(entries.first.type, 'VERDICT_REFUSED');
      expect(
        entries.first.payload['rejection_reason'],
        'GPS data was inconclusive for this route.',
      );
      expect(entries.first.payload['verdict_evidence'], isNotNull);
      expect(entries.first.payload['actor_email'], 'auditor@veraprob.com');
    });

    test('updates queue entry status to rejected', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        const RejectSanctionCommand(
          queueEntryId: 'entry-001',
          rejectedByUserId: 'auditor-1',
          actorEmail: 'auditor@veraprob.com',
          rejectionReason: 'GPS data was inconclusive for this route.',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
      );

      final pending = await queueRepo.findPending(organizationId: 'org-1');
      expect(pending, isEmpty);
    });
  });
}
