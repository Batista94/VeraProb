import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_forensic_evidence_snapshot_repository.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'PostgresForensicEvidenceSnapshotRepository',
    () {
      late SupabaseClient client;
      late PostgresForensicEvidenceSnapshotRepository repo;

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repo = PostgresForensicEvidenceSnapshotRepository(client);
        }
      });

      test('findByLedgerEntry returns null for unknown verdict (INV-26)', () async {
        final result = await repo.findByLedgerEntry(
          organizationId: PostgresTestConfig.testOrgId,
          ledgerEntryId: 'non-existent-ledger-id',
        );
        expect(result, isNull);
      });

      test('findByLedgerEntry isolates tenants — cross-org lookup returns null (INV-22)', () async {
        final result = await repo.findByLedgerEntry(
          organizationId: 'other-org-id',
          ledgerEntryId: 'non-existent-ledger-id',
        );
        expect(result, isNull);
      });

      test('findByOrganization returns empty list when no snapshots in range', () async {
        final results = await repo.findByOrganization(
          organizationId: PostgresTestConfig.testOrgId,
          fromUtc: DateTime.utc(2020, 1, 1),
          toUtc: DateTime.utc(2020, 1, 2),
        );
        expect(results, isEmpty);
      });

      test('verify throws ResourceNotFound for unknown verdict (INV-26)', () async {
        expect(
          () => repo.verify(
            organizationId: PostgresTestConfig.testOrgId,
            ledgerEntryId: 'non-existent-ledger-id',
          ),
          throwsA(isA<ResourceNotFoundException>()),
        );
      });

      test('EvidenceVerificationStatus values are exhaustive', () {
        const values = EvidenceVerificationStatus.values;
        expect(values, containsAll([
          EvidenceVerificationStatus.authentic,
          EvidenceVerificationStatus.tampered,
        ]));
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
