import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  late InMemorySlaAuditLedgerRepository repo;

  setUp(() {
    repo = InMemorySlaAuditLedgerRepository();
  });

  SlaLedgerEntry makeEntry({
    String organizationId = 'org-1',
    String contractId = 'contract-1',
    String? setId = 'set-1',
    String type = 'PLAN_DECLARED',
    DateTime? occurredAtUtc,
  }) {
    return SlaLedgerEntry(
      organizationId: organizationId,
      contractId: contractId,
      setId: setId,
      type: type,
      planVersion: 1,
      occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 1, 1),
    );
  }

  group('InMemorySlaAuditLedgerRepository', () {
    group('append', () {
      test('returns a non-null UUID event ID', () async {
        final eventId = await repo.append(makeEntry());
        expect(eventId, isNotEmpty);
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(eventId),
          isTrue,
        );
      });

      test('assigns auto-incrementing integer IDs', () async {
        await repo.append(makeEntry());
        await repo.append(makeEntry());
        final entries = repo.entries;
        expect(entries[0].id, 1);
        expect(entries[1].id, 2);
      });

      test('appended entry is visible via entries getter', () async {
        expect(repo.entries, isEmpty);
        await repo.append(makeEntry());
        expect(repo.entries, hasLength(1));
      });

      test('organizationId is preserved on stored entry', () async {
        await repo.append(makeEntry(organizationId: 'org-special'));
        expect(repo.entries.first.organizationId, 'org-special');
      });

      test('payload is preserved on stored entry', () async {
        final entry = SlaLedgerEntry(
          organizationId: 'org-1',
          contractId: 'c-1',
          type: 'PLAN_DECLARED',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
          payload: {'key': 'value', 'count': 42},
        );
        await repo.append(entry);
        expect(repo.entries.first.payload, {'key': 'value', 'count': 42});
      });
    });

    group('getLastEntryId', () {
      test('returns null when repository is empty', () async {
        final result = await repo.getLastEntryId();
        expect(result, isNull);
      });

      test('returns null for org with no entries (tenant isolation)', () async {
        await repo.append(makeEntry(organizationId: 'org-A'));
        final result = await repo.getLastEntryId(organizationId: 'org-B');
        expect(result, isNull);
      });

      test('returns eventId of the last appended entry', () async {
        await repo.append(makeEntry());
        final secondId = await repo.append(makeEntry());
        final result = await repo.getLastEntryId(organizationId: 'org-1');
        expect(result, secondId);
      });

      test('tenant isolation: org-A last entry not returned for org-B', () async {
        final orgAId = await repo.append(makeEntry(organizationId: 'org-A'));
        await repo.append(makeEntry(organizationId: 'org-B'));

        final resultA = await repo.getLastEntryId(organizationId: 'org-A');
        expect(resultA, orgAId);
      });

      test('without organizationId: returns last entry across all orgs', () async {
        await repo.append(makeEntry(organizationId: 'org-A'));
        final lastId = await repo.append(makeEntry(organizationId: 'org-B'));

        final result = await repo.getLastEntryId();
        expect(result, lastId);
      });
    });

    group('getEntriesBySetId', () {
      test('returns empty list for unknown setId', () async {
        final results = await repo.getEntriesBySetId(
          'unknown-set',
          organizationId: 'org-1',
        );
        expect(results, isEmpty);
      });

      test('returns entries matching setId for correct org', () async {
        await repo.append(makeEntry(organizationId: 'org-1', setId: 'set-A'));
        await repo.append(makeEntry(organizationId: 'org-1', setId: 'set-B'));

        final results = await repo.getEntriesBySetId(
          'set-A',
          organizationId: 'org-1',
        );
        expect(results, hasLength(1));
        expect(results.first.setId, 'set-A');
      });

      test('tenant isolation: setId match ignored for wrong org', () async {
        await repo.append(makeEntry(organizationId: 'org-A', setId: 'set-1'));

        final results = await repo.getEntriesBySetId(
          'set-1',
          organizationId: 'org-B',
        );
        expect(results, isEmpty);
      });

      test('without organizationId: returns all entries matching setId across orgs',
          () async {
        await repo.append(makeEntry(organizationId: 'org-A', setId: 'set-1'));
        await repo.append(makeEntry(organizationId: 'org-B', setId: 'set-1'));
        await repo.append(makeEntry(organizationId: 'org-A', setId: 'set-2'));

        final results = await repo.getEntriesBySetId('set-1');
        expect(results, hasLength(2));
      });

      test('entries are sorted chronologically by occurredAtUtc ascending', () async {
        await repo.append(
          makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 3), setId: 'set-1'),
        );
        await repo.append(
          makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 1), setId: 'set-1'),
        );
        await repo.append(
          makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 2), setId: 'set-1'),
        );

        final results = await repo.getEntriesBySetId(
          'set-1',
          organizationId: 'org-1',
        );
        expect(results[0].occurredAtUtc, DateTime.utc(2026, 1, 1));
        expect(results[1].occurredAtUtc, DateTime.utc(2026, 1, 2));
        expect(results[2].occurredAtUtc, DateTime.utc(2026, 1, 3));
      });

      test('multiple sets: entries for set-A do not bleed into set-B', () async {
        await repo.append(makeEntry(setId: 'set-A'));
        await repo.append(makeEntry(setId: 'set-B'));
        await repo.append(makeEntry(setId: 'set-A'));

        final resultsA = await repo.getEntriesBySetId(
          'set-A',
          organizationId: 'org-1',
        );
        final resultsB = await repo.getEntriesBySetId(
          'set-B',
          organizationId: 'org-1',
        );
        expect(resultsA, hasLength(2));
        expect(resultsB, hasLength(1));
      });
    });
  });
}
