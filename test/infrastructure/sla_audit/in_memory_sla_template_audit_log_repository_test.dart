import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_audit_log_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  late InMemorySlaTemplateAuditLogRepository repo;
  late FakeDateTimeProvider clock;

  setUp(() {
    repo = InMemorySlaTemplateAuditLogRepository();
    clock = FakeDateTimeProvider(DateTime.utc(2026, 5, 29, 12, 0));
  });

  SlaTemplateAuditEntry makeEntry({
    String organizationId = 'org-1',
    String templateId = 'tmpl-1',
    String actorSessionId = 'sess-1',
    String action = 'CREATED',
    Map<String, dynamic>? snapshot,
  }) {
    return SlaTemplateAuditEntry.create(
      organizationId: organizationId,
      templateId: templateId,
      actorSessionId: actorSessionId,
      action: action,
      templateSnapshot: snapshot ?? {'name': 'SLA Gold', 'version': 1},
      clock: clock,
    );
  }

  group('InMemorySlaTemplateAuditLogRepository', () {
    // ── Happy Path ───────────────────────────────────────────────────────────
    group('Happy Path — append', () {
      test('appends entry successfully and preserves all properties', () async {
        final entry = makeEntry(organizationId: 'org-special');
        await repo.append(entry);

        expect(repo.entries, hasLength(1));
        final stored = repo.entries.first;

        expect(stored.id, equals(entry.id));
        expect(stored.organizationId, equals('org-special'));
        expect(stored.templateId, equals(entry.templateId));
        expect(stored.actorSessionId, equals(entry.actorSessionId));
        expect(stored.action, equals(entry.action));
        expect(stored.templateSnapshot, equals(entry.templateSnapshot));
        expect(stored.occurredAtUtc, equals(entry.occurredAtUtc));
      });
    });

    // ── CIA Triad: Integrity ──────────────────────────────────────────────────
    group('CIA Integrity — immutability & order', () {
      test(
        'entries list is unmodifiable externally (no direct mutation)',
        () async {
          final entry = makeEntry();
          await repo.append(entry);

          final list = repo.entries;
          expect(() => list.add(makeEntry()), throwsUnsupportedError);
          expect(() => list.clear(), throwsUnsupportedError);
        },
      );

      test('entries are stored in chronological order of insertion', () async {
        final entry1 = makeEntry(templateId: 'tmpl-1');
        clock.advance(const Duration(minutes: 1));
        final entry2 = makeEntry(templateId: 'tmpl-2');
        clock.advance(const Duration(minutes: 1));
        final entry3 = makeEntry(templateId: 'tmpl-3');

        await repo.append(entry1);
        await repo.append(entry2);
        await repo.append(entry3);

        expect(repo.entries, hasLength(3));
        expect(repo.entries[0].templateId, equals('tmpl-1'));
        expect(repo.entries[1].templateId, equals('tmpl-2'));
        expect(repo.entries[2].templateId, equals('tmpl-3'));
      });
    });

    // ── Adverse Scenarios ─────────────────────────────────────────────────────
    group('Adverse Scenarios — duplicate PKs', () {
      test('appending duplicate entry ID throws IntegrityException', () async {
        final entry = makeEntry();
        await repo.append(entry);

        // Attempting to append the exact same entry (with same ID) must throw
        expect(
          () => repo.append(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('already exists'),
            ),
          ),
        );

        // Ensure the entry was not added twice
        expect(repo.entries, hasLength(1));
      });
    });

    // ── CIA Triad: Confidentiality ───────────────────────────────────────────
    group('CIA Confidentiality — tenant isolation', () {
      test(
        'filter entries by organizationId isolates Tenant-A from Tenant-B',
        () async {
          final entryA1 = makeEntry(
            organizationId: 'org-A',
            templateId: 'tmpl-A1',
          );
          final entryB1 = makeEntry(
            organizationId: 'org-B',
            templateId: 'tmpl-B1',
          );
          final entryA2 = makeEntry(
            organizationId: 'org-A',
            templateId: 'tmpl-A2',
          );

          await repo.append(entryA1);
          await repo.append(entryB1);
          await repo.append(entryA2);

          // Retrieve entries for org-A
          final orgAEntries = repo.entries
              .where((e) => e.organizationId == 'org-A')
              .toList();
          expect(orgAEntries, hasLength(2));
          expect(orgAEntries.any((e) => e.templateId == 'tmpl-B1'), isFalse);

          // Retrieve entries for org-B
          final orgBEntries = repo.entries
              .where((e) => e.organizationId == 'org-B')
              .toList();
          expect(orgBEntries, hasLength(1));
          expect(orgBEntries.first.templateId, equals('tmpl-B1'));
        },
      );
    });

    // ── CIA Triad: Availability ───────────────────────────────────────────────
    group('CIA Availability — concurrency safety', () {
      test(
        'concurrent appends do not cause race conditions or drop events',
        () async {
          final entries = List.generate(
            50,
            (i) => makeEntry(organizationId: 'org-$i', templateId: 'tmpl-$i'),
          );

          // Run append operations concurrently
          await Future.wait(entries.map((e) => repo.append(e)));

          expect(repo.entries, hasLength(50));
          // Verify all elements exist in the stored list
          final storedIds = repo.entries.map((e) => e.id).toSet();
          expect(storedIds, hasLength(50));
          for (final entry in entries) {
            expect(storedIds.contains(entry.id), isTrue);
          }
        },
      );
    });
  });
}
