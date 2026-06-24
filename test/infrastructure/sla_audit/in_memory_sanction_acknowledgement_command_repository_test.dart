import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  late InMemorySanctionReviewQueueRepository queue;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemorySanctionAcknowledgementCommandRepository repo;

  final evidence = VerdictEvidence.create(
    clauseRef: 'rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 6, 10),
    deltaValue: 15,
    thresholdValue: 0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry entry(SanctionReviewStatus status) =>
      SanctionReviewQueueEntry(
        id: 'entry-1',
        organizationId: 'org-1',
        ledgerEntryId: 'ledger-1',
        setId: 'set-1',
        contractId: 'contract-1',
        verdictEvidence: evidence,
        status: status,
        createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
      );

  setUp(() {
    queue = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    repo = InMemorySanctionAcknowledgementCommandRepository(
      queueRepo: queue,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12)),
    );
  });

  test(
    'applied → SANCTION_ACKNOWLEDGED ledger fact + terminal acknowledged',
    () async {
      await queue.enqueue(entry(SanctionReviewStatus.applied));

      final id = await repo.acknowledgeInternal(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        acknowledgedByUserId: 'user-1',
        notes: 'aceito por telefone',
      );

      expect(id, isNotEmpty);
      final updated = await queue.findById('entry-1', organizationId: 'org-1');
      expect(updated!.status, SanctionReviewStatus.acknowledged);
      final acks = ledger.entries.where(
        (e) => e.type == 'SANCTION_ACKNOWLEDGED',
      );
      expect(acks, hasLength(1));
      expect(acks.first.payload['method'], 'INTERNAL_RECORD');
      expect(acks.first.payload['acknowledged_by'], 'user-1');
    },
  );

  test('non-applied state is rejected (anti-oracle parity with RPC)', () async {
    await queue.enqueue(entry(SanctionReviewStatus.pending));
    expect(
      () => repo.acknowledgeInternal(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        acknowledgedByUserId: 'user-1',
      ),
      throwsA(isA<DomainException>()),
    );
  });

  test('missing / wrong-org entry is rejected', () async {
    expect(
      () => repo.acknowledgeInternal(
        organizationId: 'org-1',
        queueEntryId: 'nope',
        acknowledgedByUserId: 'user-1',
      ),
      throwsA(isA<DomainException>()),
    );
  });

  test('no ledger fact is appended on rejection', () async {
    await queue.enqueue(entry(SanctionReviewStatus.pending));
    try {
      await repo.acknowledgeInternal(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        acknowledgedByUserId: 'user-1',
      );
    } on DomainException {
      // expected
    }
    expect(ledger.entries, isEmpty);
  });
}
