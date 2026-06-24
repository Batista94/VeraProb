import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

/// Mirrors the `approve_sanction` / `reject_sanction` RPC semantics in memory:
/// status re-check, single-fact append, anti-oracle posture, and the
/// verdict-already-exists idempotency backstop.
void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemorySanctionReviewCommandRepository repo;

  final evidence = VerdictEvidence.create(
    clauseRef: 'no-show-rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 8, 12, 10, 0),
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry pendingEntry() => SanctionReviewQueueEntry(
    id: 'entry-1',
    organizationId: 'org-1',
    ledgerEntryId: 'ledger-1',
    setId: 'set-1',
    contractId: 'contract-1',
    verdictEvidence: evidence,
    status: SanctionReviewStatus.pending,
    createdAtUtc: DateTime.utc(2026, 8, 12, 10, 5),
  );

  final now = DateTime.utc(2026, 8, 12, 12, 0);

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    repo = InMemorySanctionReviewCommandRepository(
      queueRepo: queueRepo,
      ledger: ledger,
    );
  });

  test('approve appends one VERDICT_SEALED and flips to applied', () async {
    await queueRepo.enqueue(pendingEntry());

    final result = await repo.approveSanction(
      organizationId: 'org-1',
      queueEntryId: 'entry-1',
      reviewedByUserId: 'auditor-1',
      actorEmail: 'auditor@test.com',
      occurredAtUtc: now,
    );

    expect(result.finalQueueStatus, 'applied');
    expect(ledger.entries.where((e) => e.type == 'VERDICT_SEALED').length, 1);
    expect(await queueRepo.findPending(organizationId: 'org-1'), isEmpty);
  });

  test('reject with empty reason fails closed (anti-oracle)', () async {
    await queueRepo.enqueue(pendingEntry());

    expect(
      () => repo.rejectSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        rejectionReason: '   ',
        reasonCode: 'SENSOR_FAULT',
        occurredAtUtc: now,
      ),
      throwsA(isA<SovereigntyViolationException>()),
    );
  });

  test('reject with empty reasonCode fails closed (BUG-01)', () async {
    await queueRepo.enqueue(pendingEntry());

    expect(
      () => repo.rejectSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        rejectionReason: 'GPS data was inconclusive for this route.',
        reasonCode: '   ',
        occurredAtUtc: now,
      ),
      throwsA(isA<SovereigntyViolationException>()),
    );
  });

  test(
    'reject seals VERDICT_REFUSED with the structured reason_code',
    () async {
      await queueRepo.enqueue(pendingEntry());

      final result = await repo.rejectSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        rejectionReason: 'GPS data was inconclusive for this route.',
        reasonCode: 'SENSOR_FAULT',
        occurredAtUtc: now,
      );

      expect(result.finalQueueStatus, 'rejected');
      final refused = ledger.entries.firstWhere(
        (e) => e.type == 'VERDICT_REFUSED',
      );
      expect(refused.payload['reason_code'], 'SENSOR_FAULT');
    },
  );

  group('generateDisputePortalToken (BUG-02)', () {
    test('mints a token + logs the fact for a disputed entry', () async {
      await queueRepo.enqueue(
        pendingEntry().copyWith(status: SanctionReviewStatus.disputed),
      );

      final token = await repo.generateDisputePortalToken(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        createdByUserId: 'auditor-1',
      );

      expect(token, isNotEmpty);
      expect(
        ledger.entries
            .where((e) => e.type == 'DISPUTE_PORTAL_TOKEN_GENERATED')
            .length,
        1,
      );
    });

    test('rejects a still-pending entry (not contested)', () async {
      await queueRepo.enqueue(pendingEntry());

      expect(
        () => repo.generateDisputePortalToken(
          organizationId: 'org-1',
          queueEntryId: 'entry-1',
          createdByUserId: 'auditor-1',
        ),
        throwsA(isA<IdempotencyProcessingException>()),
      );
    });

    test(
      'missing entry is indistinguishable from wrong-org (INV-26)',
      () async {
        expect(
          () => repo.generateDisputePortalToken(
            organizationId: 'org-1',
            queueEntryId: 'does-not-exist',
            createdByUserId: 'auditor-1',
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });

  test('missing entry is indistinguishable from wrong-org (INV-26)', () async {
    expect(
      () => repo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'does-not-exist',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        occurredAtUtc: now,
      ),
      throwsA(isA<SovereigntyViolationException>()),
    );
  });

  test('second approve on a non-pending entry loses (idempotency)', () async {
    await queueRepo.enqueue(pendingEntry());
    await repo.approveSanction(
      organizationId: 'org-1',
      queueEntryId: 'entry-1',
      reviewedByUserId: 'auditor-1',
      actorEmail: 'auditor@test.com',
      occurredAtUtc: now,
    );

    expect(
      () => repo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-2',
        actorEmail: 'auditor2@test.com',
        occurredAtUtc: now,
      ),
      throwsA(isA<IdempotencyProcessingException>()),
    );
    expect(ledger.entries.where((e) => e.type == 'VERDICT_SEALED').length, 1);
  });

  test(
    'verdict-already-exists backstop blocks a still-pending re-append',
    () async {
      // Simulate a torn state: a VERDICT fact exists while the row is still
      // pending. The backstop must reject the second append (no duplicate fact).
      final entry = pendingEntry();
      await queueRepo.enqueue(entry);
      await ledger.append(
        SlaLedgerEntry(
          organizationId: entry.organizationId,
          type: 'VERDICT_SEALED',
          operatorId: 'auditor-1',
          setId: entry.setId,
          contractId: entry.contractId,
          planVersion: 0,
          occurredAtUtc: now,
          payload: {'queue_entry_id': entry.id},
        ),
      );

      expect(
        () => repo.approveSanction(
          organizationId: 'org-1',
          queueEntryId: 'entry-1',
          reviewedByUserId: 'auditor-1',
          actorEmail: 'auditor@test.com',
          occurredAtUtc: now,
        ),
        throwsA(isA<IdempotencyProcessingException>()),
      );
    },
  );

  group('dual-control (threshold ON at 100000; fine is 150000)', () {
    late InMemorySanctionReviewCommandRepository dcRepo;

    setUp(() {
      dcRepo = InMemorySanctionReviewCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
        dualControlThresholdCents: 100000,
      );
    });

    test('high-value approve forks to pending_peer_review (no seal)', () async {
      await queueRepo.enqueue(pendingEntry());

      final result = await dcRepo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        occurredAtUtc: now,
      );

      expect(result.finalQueueStatus, 'pending_peer_review');
      final entry = await queueRepo.findById(
        'entry-1',
        organizationId: 'org-1',
      );
      expect(entry!.status, SanctionReviewStatus.pendingPeerReview);
      expect(entry.firstReviewerId, 'auditor-1');
      expect(
        ledger.entries.where((e) => e.type == 'PEER_REVIEW_REQUESTED').length,
        1,
      );
      expect(ledger.entries.where((e) => e.type == 'VERDICT_SEALED'), isEmpty);
    });

    test('requester cannot self-confirm their own verdict', () async {
      await queueRepo.enqueue(pendingEntry());
      await dcRepo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        occurredAtUtc: now,
      );

      expect(
        () => dcRepo.confirmPeerReview(
          organizationId: 'org-1',
          queueEntryId: 'entry-1',
          reviewedByUserId: 'auditor-1', // same as first reviewer
          actorEmail: 'auditor@test.com',
          occurredAtUtc: now,
        ),
        throwsA(isA<DualControlSelfApprovalException>()),
      );
    });

    test(
      'distinct second auditor confirms → applied + dual signature',
      () async {
        await queueRepo.enqueue(pendingEntry());
        await dcRepo.approveSanction(
          organizationId: 'org-1',
          queueEntryId: 'entry-1',
          reviewedByUserId: 'auditor-1',
          actorEmail: 'auditor@test.com',
          occurredAtUtc: now,
        );

        final result = await dcRepo.confirmPeerReview(
          organizationId: 'org-1',
          queueEntryId: 'entry-1',
          reviewedByUserId: 'auditor-2',
          actorEmail: 'auditor2@test.com',
          occurredAtUtc: now,
        );

        expect(result.finalQueueStatus, 'applied');
        final seal = ledger.entries.firstWhere(
          (e) => e.type == 'VERDICT_SEALED',
        );
        expect(seal.payload['first_reviewer_id'], 'auditor-1');
        expect(seal.payload['second_reviewer_id'], 'auditor-2');
      },
    );

    test('decline reverts a peer review to its origin (pending)', () async {
      await queueRepo.enqueue(pendingEntry());
      await dcRepo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-1',
        actorEmail: 'auditor@test.com',
        occurredAtUtc: now,
      );

      final result = await dcRepo.declinePeerReview(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        reviewedByUserId: 'auditor-2',
        actorEmail: 'auditor2@test.com',
        reason: 'Need more context.',
        occurredAtUtc: now,
      );

      expect(result.finalQueueStatus, 'pending');
      final entry = await queueRepo.findById(
        'entry-1',
        organizationId: 'org-1',
      );
      expect(entry!.status, SanctionReviewStatus.pending);
      expect(
        ledger.entries.where((e) => e.type == 'PEER_REVIEW_DECLINED').length,
        1,
      );
    });
  });
}
