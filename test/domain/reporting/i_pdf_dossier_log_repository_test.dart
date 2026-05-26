// Contract tests for IPdfDossierLogRepository.
//
// Verifies that the port contract is satisfied by fake implementations,
// covering INV-1 (org isolation), INV-3 (append semantics), and
// INV-9 (chain of custody — documentHash must be recorded).

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/reporting/i_pdf_dossier_log_repository.dart';

// ── Fake ──────────────────────────────────────────────────────────────────────

class _InMemoryPdfDossierLogRepository implements IPdfDossierLogRepository {
  final List<Map<String, String>> log = [];

  @override
  Future<void> logGeneration({
    required String organizationId,
    required String slaLedgerEntryId,
    required String documentHash,
    required String operatorId,
  }) async {
    log.add({
      'organizationId': organizationId,
      'slaLedgerEntryId': slaLedgerEntryId,
      'documentHash': documentHash,
      'operatorId': operatorId,
    });
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('IPdfDossierLogRepository — Contract', () {
    late _InMemoryPdfDossierLogRepository repo;

    setUp(() {
      repo = _InMemoryPdfDossierLogRepository();
    });

    test('logGeneration records all required fields (INV-9)', () async {
      await repo.logGeneration(
        organizationId: 'org-aaa',
        slaLedgerEntryId: 'entry-111',
        documentHash: 'sha256-abc',
        operatorId: 'user-xyz',
      );

      expect(repo.log, hasLength(1));
      final entry = repo.log.first;
      expect(entry['organizationId'], equals('org-aaa'));
      expect(entry['slaLedgerEntryId'], equals('entry-111'));
      expect(entry['documentHash'], equals('sha256-abc'));
      expect(entry['operatorId'], equals('user-xyz'));
    });

    test('logGeneration is scoped to organizationId (INV-1)', () async {
      await repo.logGeneration(
        organizationId: 'org-a',
        slaLedgerEntryId: 'entry-1',
        documentHash: 'hash-1',
        operatorId: 'op-1',
      );
      await repo.logGeneration(
        organizationId: 'org-b',
        slaLedgerEntryId: 'entry-2',
        documentHash: 'hash-2',
        operatorId: 'op-2',
      );

      final orgALogs = repo.log.where((e) => e['organizationId'] == 'org-a');
      final orgBLogs = repo.log.where((e) => e['organizationId'] == 'org-b');

      // Neither org's entries bleed into the other (append, never mutate).
      expect(orgALogs, hasLength(1));
      expect(orgBLogs, hasLength(1));
    });

    test(
      'logGeneration is append-only — multiple calls accumulate (INV-3)',
      () async {
        for (var i = 0; i < 3; i++) {
          await repo.logGeneration(
            organizationId: 'org-x',
            slaLedgerEntryId: 'entry-$i',
            documentHash: 'hash-$i',
            operatorId: 'op',
          );
        }

        // All 3 entries are present — none replaced the previous (append-only).
        expect(repo.log, hasLength(3));
        final hashes = repo.log.map((e) => e['documentHash']).toList();
        expect(hashes, containsAll(['hash-0', 'hash-1', 'hash-2']));
      },
    );

    test('documentHash is stored verbatim (INV-9 — SHA-256 seal)', () async {
      const expectedHash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      await repo.logGeneration(
        organizationId: 'org-z',
        slaLedgerEntryId: 'entry-z',
        documentHash: expectedHash,
        operatorId: 'user-z',
      );

      expect(repo.log.first['documentHash'], equals(expectedHash));
    });
  });
}
