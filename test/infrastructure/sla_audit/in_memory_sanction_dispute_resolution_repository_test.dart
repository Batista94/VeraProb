import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_dispute_resolution_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

/// Direct unit coverage for the in-memory dispute-resolution fake.
///
/// The fake mirrors the `resolve_dispute` SECURITY DEFINER RPC for in-memory
/// persistence mode + handler unit tests. The handler suite exercises it
/// transitively; this suite pins its standalone contract so the atomic
/// semantics (anti-oracle reject, idempotency backstop, overturn seal) cannot
/// regress silently behind the port.
void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryForensicEvidenceSnapshotRepository vault;
  late InMemorySanctionDisputeResolutionRepository repo;

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

  SanctionReviewQueueEntry makeDisputedEntry({
    String id = 'entry-001',
    String orgId = 'org-1',
    SanctionReviewStatus status = SanctionReviewStatus.disputed,
  }) {
    return SanctionReviewQueueEntry(
      id: id,
      organizationId: orgId,
      ledgerEntryId: 'ledger-001',
      setId: 'set-1',
      contractId: 'contract-1',
      verdictEvidence: evidence,
      status: status,
      createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
      reviewedAtUtc: DateTime.utc(2026, 4, 6, 10, 6),
      reviewedByUserId: 'auditor-disputer',
    );
  }

  Future<void> seedOpenDispute({String queueEntryId = 'entry-001'}) async {
    await ledger.append(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'SANCTION_DISPUTED',
        operatorId: 'CONTRACTOR',
        setId: 'set-1',
        contractId: 'contract-1',
        planVersion: 0,
        occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 6),
        payload: {'queue_entry_id': queueEntryId},
      ),
    );
  }

  Future<dynamic> resolve({
    String resolution = 'DISPUTE_ACCEPTED',
    String? reason = 'Contractor proved force majeure.',
    String organizationId = 'org-1',
  }) {
    return repo.resolveDispute(
      organizationId: organizationId,
      queueEntryId: 'entry-001',
      resolution: resolution,
      resolutionReason: reason,
      resolvedByUserId: 'auditor-1',
      actorEmail: 'auditor@veraprob.com',
      occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 7),
      idempotencyKey: 'entry-001:$resolution:SNAPSHOT',
    );
  }

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    vault = InMemoryForensicEvidenceSnapshotRepository()
      ..seedRules(
        organizationId: 'org-1',
        contractId: 'contract-1',
        ruleSetId: 'ruleset-001',
        rules: [
          {
            'rule_id': 'rule-001',
            'rule_type': 'speed_violation',
            'rule_config': <String, dynamic>{},
            'rule_version': 1,
            'evaluation_order': 1,
          },
        ],
        slaRuleVersion: 1,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
    repo = InMemorySanctionDisputeResolutionRepository(
      queueRepo: queueRepo,
      ledger: ledger,
      vault: vault,
    );
  });

  test(
    'accept appends DISPUTE_ACCEPTED, flips status, returns result',
    () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      final result = await resolve();

      expect(result.finalQueueStatus, 'rejected');
      expect(result.snapshot, isNull);

      final last = ledger.entries.last;
      expect(last.type, 'DISPUTE_ACCEPTED');
      expect(result.ledgerEntryId, last.eventId);

      final entry = await queueRepo.findById(
        'entry-001',
        organizationId: 'org-1',
      );
      expect(entry!.status, SanctionReviewStatus.rejected);
      expect(entry.rejectionReason, 'Contractor proved force majeure.');
    },
  );

  test(
    'missing / wrong-org entry → SovereigntyViolationException (INV-26)',
    () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(
        resolve(organizationId: 'org-2'),
        throwsA(isA<SovereigntyViolationException>()),
      );
    },
  );

  test('non-disputed entry → IdempotencyProcessingException', () async {
    await queueRepo.enqueue(
      makeDisputedEntry(status: SanctionReviewStatus.pending),
    );
    await seedOpenDispute();

    await expectLater(
      resolve(),
      throwsA(isA<IdempotencyProcessingException>()),
    );
  });

  test('existing resolution fact (unique-index backstop) → Idempotency, no '
      'second append', () async {
    await queueRepo.enqueue(makeDisputedEntry());
    await seedOpenDispute();
    await ledger.append(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'DISPUTE_ACCEPTED',
        operatorId: 'auditor-other',
        setId: 'set-1',
        contractId: 'contract-1',
        planVersion: 0,
        occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 7),
        payload: {'queue_entry_id': 'entry-001'},
      ),
    );
    final before = ledger.entries.length;

    await expectLater(
      resolve(),
      throwsA(isA<IdempotencyProcessingException>()),
    );
    expect(ledger.entries.length, before);
  });

  test('overturn seals a forensic snapshot inline (INV-21)', () async {
    await queueRepo.enqueue(makeDisputedEntry());
    await seedOpenDispute();

    final result = await resolve(resolution: 'DISPUTE_OVERTURNED');

    expect(result.finalQueueStatus, 'applied');
    expect(result.snapshot, isNotNull);
    expect(result.snapshot!['verdict_type'], 'DISPUTE_OVERTURNED');
    expect(vault.count, 1);

    final entry = await queueRepo.findById(
      'entry-001',
      organizationId: 'org-1',
    );
    expect(entry!.status, SanctionReviewStatus.applied);
  });
}
