import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_command.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late RejectSanctionHandler handler;

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
    handler = RejectSanctionHandler(
      queueRepo: queueRepo,
      ledger: ledger,
      rbac: RbacService(),
    );
  });

  group('RBAC', () {
    test('throws DomainException for operator role', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'user-op',
            rejectionReason: 'GPS data was inconclusive.',
            callerRole: UserRole.operator,
            organizationId: 'org-1',
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
          RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            rejectionReason: 'too short', // 9 chars
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for reason that is only whitespace', () async {
      await queueRepo.enqueue(makePendingEntry());

      expect(
        () => handler.handle(
          RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            rejectionReason: '          ', // 10 spaces, trims to empty
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts reason with exactly 10 chars after trim', () async {
      await queueRepo.enqueue(makePendingEntry());

      await expectLater(
        handler.handle(
          RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            rejectionReason: '  1234567890  ', // 10 non-whitespace chars
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
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
          RejectSanctionCommand(
            queueEntryId: 'entry-001',
            rejectedByUserId: 'auditor-1',
            rejectionReason: 'GPS data was inconclusive for this route.',
            callerRole: UserRole.auditor,
            organizationId: 'org-1',
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Happy path', () {
    test('appends SANCTION_REJECTED to ledger with reason', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        RejectSanctionCommand(
          queueEntryId: 'entry-001',
          rejectedByUserId: 'auditor-1',
          rejectionReason: 'GPS data was inconclusive for this route.',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
        ),
      );

      final entries = ledger.entries;
      expect(entries.length, 1);
      expect(entries.first.type, 'SANCTION_REJECTED');
      expect(
        entries.first.payload['rejection_reason'],
        'GPS data was inconclusive for this route.',
      );
      expect(entries.first.payload['verdict_evidence'], isNotNull);
    });

    test('updates queue entry status to rejected', () async {
      await queueRepo.enqueue(makePendingEntry());

      await handler.handle(
        RejectSanctionCommand(
          queueEntryId: 'entry-001',
          rejectedByUserId: 'auditor-1',
          rejectionReason: 'GPS data was inconclusive for this route.',
          callerRole: UserRole.auditor,
          organizationId: 'org-1',
        ),
      );

      final pending = await queueRepo.findPending(organizationId: 'org-1');
      expect(pending, isEmpty);
    });
  });
}
