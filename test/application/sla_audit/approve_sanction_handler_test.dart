import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_command.dart';
import 'package:veraprob/application/sla_audit/approve_sanction_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ApproveSanctionHandler handler;
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

  SanctionReviewQueueEntry makePendingEntry({
    String id = 'entry-001',
    String orgId = 'org-1',
  }) {
    return SanctionReviewQueueEntry(
      id: id,
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
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    handler = ApproveSanctionHandler(
      tenantValidator: tenantValidator,
      queueRepo: queueRepo,
      reviewRepo: InMemorySanctionReviewCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
      ),
      rbac: RbacService(),
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
          const ApproveSanctionCommand(
            queueEntryId: 'entry-001',
            approvedByUserId: 'user-op',
            actorEmail: 'op@test.com',
            callerRole: UserRole.operator,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for contractorViewer role', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          const ApproveSanctionCommand(
            queueEntryId: 'entry-001',
            approvedByUserId: 'user-cv',
            actorEmail: 'cv@test.com',
            callerRole: UserRole.contractorViewer,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('allows auditor role', () async {
      await queueRepo.enqueue(makePendingEntry());

      await expectLater(
        handler.handle(
          const ApproveSanctionCommand(
            queueEntryId: 'entry-001',
            approvedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        completes,
      );
    });

    test('allows admin role', () async {
      await queueRepo.enqueue(makePendingEntry());

      await expectLater(
        handler.handle(
          const ApproveSanctionCommand(
            queueEntryId: 'entry-001',
            approvedByUserId: 'admin-1',
            actorEmail: 'admin@test.com',
            callerRole: UserRole.admin,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        completes,
      );
    });
  });

  group('Idempotency (INV-24)', () {
    test('throws DomainException if entry already applied', () async {
      final appliedEntry = makePendingEntry().copyWith(
        status: SanctionReviewStatus.applied,
      );
      await queueRepo.enqueue(
        SanctionReviewQueueEntry(
          id: appliedEntry.id,
          organizationId: appliedEntry.organizationId,
          ledgerEntryId: 'ledger-001',
          setId: 'set-1',
          contractId: 'contract-1',
          verdictEvidence: evidence,
          status: SanctionReviewStatus.applied,
          createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
        ),
      );

      expect(
        () => handler.handle(
          const ApproveSanctionCommand(
            queueEntryId: 'entry-001',
            approvedByUserId: 'auditor-1',
            actorEmail: 'auditor@test.com',
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
            sessionId: 'session-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Tenant isolation (INV-6)', () {
    test(
      'throws SovereigntyViolationException if orgId does not match',
      () async {
        await queueRepo.enqueue(makePendingEntry(orgId: 'org-1'));

        expect(
          () => handler.handle(
            const ApproveSanctionCommand(
              queueEntryId: 'entry-001',
              approvedByUserId: 'auditor-evil',
              actorEmail: 'evil@other.com',
              callerRole: UserRole.auditor,
              organizationId: 'org-2', // wrong org
              sessionId: 'session-1',
            ),
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });

  group('Happy path', () {
    test('appends VERDICT_SEALED to ledger with actor_email', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        const ApproveSanctionCommand(
          queueEntryId: 'entry-001',
          approvedByUserId: 'auditor-1',
          actorEmail: 'auditor@veraprob.com',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
      );

      final entries = ledger.entries;
      expect(entries.length, 1);
      expect(entries.first.type, 'VERDICT_SEALED');
      expect(entries.first.payload['verdict_evidence'], isNotNull);
      expect(entries.first.payload['actor_email'], 'auditor@veraprob.com');
      expect(entries.first.payload['approved_by_user_id'], 'auditor-1');
    });

    test('updates queue entry status to applied', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        const ApproveSanctionCommand(
          queueEntryId: 'entry-001',
          approvedByUserId: 'auditor-1',
          actorEmail: 'auditor@veraprob.com',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
      );

      final pending = await queueRepo.findPending(organizationId: 'org-1');
      expect(pending, isEmpty); // no longer pending
    });
  });
}
