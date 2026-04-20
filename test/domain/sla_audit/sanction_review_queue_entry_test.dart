import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
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

  SanctionReviewQueueEntry makeEntry({
    SanctionReviewStatus status = SanctionReviewStatus.pending,
  }) {
    return SanctionReviewQueueEntry(
      id: 'entry-001',
      organizationId: 'org-1',
      ledgerEntryId: 'ledger-001',
      setId: 'set-1',
      contractId: 'contract-1',
      verdictEvidence: evidence,
      status: status,
      createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
    );
  }

  group('SanctionReviewQueueEntry', () {
    test('creates with pending status by default', () {
      final entry = makeEntry();
      expect(entry.status, SanctionReviewStatus.pending);
    });

    test('copyWith transitions to applied', () {
      final entry = makeEntry();
      final now = DateTime.utc(2026, 4, 6, 11, 0);
      final applied = entry.copyWith(
        status: SanctionReviewStatus.applied,
        reviewedAtUtc: now,
        reviewedByUserId: 'auditor-001',
      );

      expect(applied.status, SanctionReviewStatus.applied);
      expect(applied.reviewedAtUtc, now);
      expect(applied.reviewedByUserId, 'auditor-001');
      // immutable fields preserved
      expect(applied.id, entry.id);
      expect(applied.ledgerEntryId, entry.ledgerEntryId);
      expect(applied.organizationId, entry.organizationId);
    });

    test('copyWith transitions to rejected with reason', () {
      final entry = makeEntry();
      final rejected = entry.copyWith(
        status: SanctionReviewStatus.rejected,
        rejectionReason: 'GPS data inconclusive for this route.',
        reviewedByUserId: 'auditor-001',
      );

      expect(rejected.status, SanctionReviewStatus.rejected);
      expect(rejected.rejectionReason, 'GPS data inconclusive for this route.');
    });

    test('copyWith does not mutate original entry', () {
      final entry = makeEntry();
      entry.copyWith(status: SanctionReviewStatus.applied);
      expect(entry.status, SanctionReviewStatus.pending);
    });

    test('equality is based on id only', () {
      final e1 = makeEntry();
      final e2 = makeEntry(status: SanctionReviewStatus.applied);
      expect(e1, e2); // same id
    });
  });
}
