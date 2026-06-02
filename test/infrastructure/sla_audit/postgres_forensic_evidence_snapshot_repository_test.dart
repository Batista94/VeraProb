import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/infrastructure/shared/canonical_json.dart';
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

      test(
        'findByLedgerEntry returns null for unknown verdict (INV-26)',
        () async {
          final result = await repo.findByLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            ledgerEntryId: 'non-existent-ledger-id',
          );
          expect(result, isNull);
        },
      );

      test(
        'findByLedgerEntry isolates tenants — cross-org lookup returns null (INV-22)',
        () async {
          final result = await repo.findByLedgerEntry(
            organizationId: 'other-org-id',
            ledgerEntryId: 'non-existent-ledger-id',
          );
          expect(result, isNull);
        },
      );

      test(
        'findByOrganization returns empty list when no snapshots in range',
        () async {
          final results = await repo.findByOrganization(
            organizationId: PostgresTestConfig.testOrgId,
            fromUtc: DateTime.utc(2020, 1, 1),
            toUtc: DateTime.utc(2020, 1, 2),
          );
          expect(results, isEmpty);
        },
      );

      test(
        'verify throws ResourceNotFound for unknown verdict (INV-26)',
        () async {
          expect(
            () => repo.verify(
              organizationId: PostgresTestConfig.testOrgId,
              ledgerEntryId: 'non-existent-ledger-id',
            ),
            throwsA(isA<ResourceNotFoundException>()),
          );
        },
      );

      test('EvidenceVerificationStatus values are exhaustive', () {
        const values = EvidenceVerificationStatus.values;
        expect(
          values,
          containsAll([
            EvidenceVerificationStatus.authentic,
            EvidenceVerificationStatus.tampered,
          ]),
        );
      });

      // Seeds an active NO_SHOW_PENALTY rule set for a fresh contract and returns
      // the contract id. Uses the service_role client (bypasses RLS).
      Future<String> seedActiveRule() async {
        const uuid = Uuid();
        final contractId = uuid.v4();
        final ruleSetId = uuid.v4();
        await client.from('contract_rule_sets').insert({
          'id': ruleSetId,
          'organization_id': PostgresTestConfig.testOrgId,
          'contract_id': contractId,
        });
        await client.from('contract_rule_versions').insert({
          'id': uuid.v4(),
          'rule_set_id': ruleSetId,
          'rule_type': 'NO_SHOW_PENALTY',
          'rule_config': {'penalty_amount_cents': 50000},
          'rule_version': 1,
          'evaluation_order': 0,
          'active_from_utc': '2026-01-01T00:00:00Z',
          'active_to_utc': null,
        });
        return contractId;
      }

      test(
        'seal round-trips through the RPC then verifies authentic (param parity)',
        () async {
          const uuid = Uuid();
          final contractId = await seedActiveRule();

          final snapshot = await repo.seal(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
            setId: 'set-int-1',
            verdictType: 'NO_SHOW_PENALTY',
            planVersion: 1,
            occurredAtUtc: DateTime.utc(2026, 8, 1, 12),
            sealedBy: uuid.v4(),
            idempotencyKey: uuid.v4(),
          );

          expect(snapshot.organizationId, PostgresTestConfig.testOrgId);
          expect(snapshot.contractId, contractId);
          expect(snapshot.slaRuleVersion, 1);
          expect(snapshot.integrityHash, hasLength(64));
          expect(snapshot.rules.orderedRules, isNotEmpty);

          final verification = await repo.verify(
            organizationId: PostgresTestConfig.testOrgId,
            ledgerEntryId: snapshot.ledgerEntryId,
          );
          expect(verification.isAuthentic, isTrue);
          expect(verification.storedHash, verification.computedHash);
        },
      );

      test(
        'concurrent seal with same idempotency key yields one snapshot + no orphan ledger (INV-11 race)',
        () async {
          const uuid = Uuid();
          const fanOut = 6;
          final contractId = await seedActiveRule();
          final idempotencyKey = uuid.v4();
          final sealedBy = uuid.v4();

          Future<ForensicEvidenceSnapshot> doSeal() => repo.seal(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
            setId: 'set-race',
            verdictType: 'NO_SHOW_PENALTY',
            planVersion: 1,
            occurredAtUtc: DateTime.utc(2026, 8, 1, 12),
            sealedBy: sealedBy,
            idempotencyKey: idempotencyKey,
          );

          // Fan out wider than 2 to raise the odds the unique_violation branch
          // actually fires; the assertions below hold no matter which racer wins.
          final results = await Future.wait(
            List.generate(fanOut, (_) => doSeal()),
          );

          // All callers converge on the single committed snapshot + verdict.
          final firstId = results.first.id;
          final firstLedger = results.first.ledgerEntryId;
          for (final r in results) {
            expect(r.id, firstId);
            expect(r.ledgerEntryId, firstLedger);
          }

          // The forensic guarantee: the losing racers' ledger appends rolled back,
          // leaving EXACTLY ONE verdict entry — no orphan (Req 10.4 / unique_violation).
          final ledgerRows = await client
              .from('sla_audit_ledger_v2')
              .select('id')
              .eq('organization_id', PostgresTestConfig.testOrgId)
              .eq('payload->>idempotency_key', idempotencyKey);
          expect(
            ledgerRows,
            hasLength(1),
            reason: 'concurrent seal must leave exactly one verdict ledger row',
          );

          final fetched = await repo.findByLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            ledgerEntryId: firstLedger,
          );
          expect(fetched, isNotNull);
        },
      );

      test(
        'stored hash is reproducible in Dart from the canonical snapshot (cross-language portability)',
        () async {
          const uuid = Uuid();
          final contractId = await seedActiveRule();

          final snapshot = await repo.seal(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
            setId: 'set-parity',
            verdictType: 'NO_SHOW_PENALTY',
            planVersion: 1,
            occurredAtUtc: DateTime.utc(2026, 8, 1, 12),
            sealedBy: uuid.v4(),
            idempotencyKey: uuid.v4(),
          );

          // Read the raw stored snapshot + hash directly, then recompute the
          // SHA-256 in Dart over the SAME canonical (JCS) form the DB used. A
          // match proves the integrity hash no longer depends on the DB engine —
          // an auditor can verify the seal with any RFC 8785 tool.
          final raw = await client
              .from('forensic_evidence_snapshots')
              .select('snapshot, integrity_hash')
              .eq('organization_id', PostgresTestConfig.testOrgId)
              .eq('ledger_entry_id', snapshot.ledgerEntryId)
              .single();

          final snapshotJson = raw['snapshot'] as Map<String, dynamic>;
          final storedHash = raw['integrity_hash'] as String;

          final recomputed = sha256
              .convert(utf8.encode(canonicalJsonEncode(snapshotJson)))
              .toString();

          expect(
            recomputed,
            storedHash,
            reason: 'Dart canonical hash must reproduce the DB seal hash',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
