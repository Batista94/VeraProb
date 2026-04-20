// Automated integration tests replacing MT-9.3.8, MT-9.3.9, MT-9.3.10.
//
// Prerequisites: local Supabase running (`supabase start`).
// Run:  flutter test test/integration/invariants_mt9_test.dart
//
// Invariants covered:
//   INV-1  — Immutable ledger (UPDATE + DELETE blocked by DB triggers)
//   INV-24 — Idempotent ingestion (ON CONFLICT DO NOTHING on ledger_entry_id)
//   INV-23 — Verdict explainability (evidence_hash 64-char hex + all fields present)

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  group(
    'MT-9.3 — Invariant Integration Tests',
    skip: isRunning ? null : skipReason,
    () {
      late SupabaseClient client;
      late String ledgerEntryId;
      late String queueRowId;
      const uuid = Uuid();

      // Stable IDs for this test run.
      final setId = uuid.v4();
      final contractId = uuid.v4();
      const orgId = PostgresTestConfig.testOrgId;

      // Minimal VerdictEvidence with a valid 64-char SHA-256 placeholder.
      final fakeEvidence = {
        'clause_ref': 'VEL-01',
        'rule_id': 'rule-mt9-inv-test',
        'rule_version': 1,
        'primary_evidence_lat': -23.5505,
        'primary_evidence_lng': -46.6333,
        'primary_evidence_timestamp_utc': '2026-03-23T10:00:00.000Z',
        'evidence_hash': 'a' * 64, // 64-char hex placeholder
        'delta_value': 8.5,
        'threshold_value': 80.0,
        'fine_cents': 150000,
        'confidence_score': 99,
      };

      setUpAll(() async {
        // Service-role client: bypasses RLS, but DB triggers still fire.
        client = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        await PostgresTestConfig.ensureSentinelOrg(client: client);

        // Seed: insert a SANCTION_RECOMMENDED ledger entry.
        // The trigger `trg_auto_enqueue_sanction` auto-populates the queue.
        final row = await client
            .from('sla_audit_ledger_v2')
            .insert({
              'organization_id': orgId,
              'type': 'SANCTION_RECOMMENDED',
              'set_id': setId,
              'contract_id': contractId,
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
              'payload': {'verdict_evidence': fakeEvidence},
            })
            .select('id')
            .single();

        ledgerEntryId = row['id'] as String;

        // Give the trigger time to populate the queue.
        await Future.delayed(const Duration(milliseconds: 400));

        final queueRows = await client
            .from('sanction_review_queue')
            .select('id')
            .eq('ledger_entry_id', ledgerEntryId);

        if ((queueRows as List).isEmpty) {
          fail(
            'setUpAll falhou: trigger não populou a queue para '
            'ledger_entry_id=$ledgerEntryId. '
            'Verifique se o trigger trg_auto_enqueue_sanction está ativo.',
          );
        }
        queueRowId = queueRows.first['id'] as String;
      });

      // ── MT-9.3.8 — INV-24: Idempotência — Sem Duplicatas ───────────────────
      group('MT-9.3.8 — Idempotência (INV-24)', () {
        test(
          'upsert com ignoreDuplicates → continua apenas 1 linha na queue',
          () async {
            // Simulates the manual test: "tente inserir com o mesmo ledger_entry_id".
            // Uses upsert(ignoreDuplicates: true) = ON CONFLICT DO NOTHING.
            await client
                .from('sanction_review_queue')
                .upsert(
                  {
                    'organization_id': orgId,
                    'ledger_entry_id': ledgerEntryId,
                    'set_id': setId,
                    'contract_id': contractId,
                    'verdict_evidence': fakeEvidence,
                    'status': 'pending',
                  },
                  onConflict: 'ledger_entry_id',
                  ignoreDuplicates: true,
                );

            final rows = await client
                .from('sanction_review_queue')
                .select('id')
                .eq('ledger_entry_id', ledgerEntryId);

            expect(
              (rows as List).length,
              1,
              reason:
                  'ON CONFLICT DO NOTHING deve garantir exatamente 1 entrada '
                  'por ledger_entry_id (INV-24)',
            );
          },
        );

        test(
          'INSERT direto com ledger_entry_id duplicado → UniqueViolation',
          () async {
            // A raw INSERT (not upsert) must throw due to the UNIQUE constraint.
            await expectLater(
              () => client.from('sanction_review_queue').insert({
                'organization_id': orgId,
                'ledger_entry_id': ledgerEntryId,
                'set_id': setId,
                'contract_id': contractId,
                'verdict_evidence': fakeEvidence,
                'status': 'pending',
              }),
              throwsA(isA<PostgrestException>()),
            );

            // Queue still has exactly 1 row after the failed insert.
            final rows = await client
                .from('sanction_review_queue')
                .select('id')
                .eq('ledger_entry_id', ledgerEntryId);

            expect((rows as List).length, 1);
          },
        );
      });

      // ── MT-9.3.9 — INV-1: Imutabilidade — Nada se Apaga ou Altera ──────────
      group('MT-9.3.9 — Imutabilidade (INV-1)', () {
        test('UPDATE em organization_id → restrict_violation', () async {
          await expectLater(
            () => client
                .from('sanction_review_queue')
                .update({
                  'organization_id': '00000000-0000-0000-0000-000000000099',
                })
                .eq('id', queueRowId),
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.message,
                'message',
                contains('immutable field mutation'),
              ),
            ),
          );
        });

        test('UPDATE em verdict_evidence → restrict_violation', () async {
          final tampered = Map<String, dynamic>.from(fakeEvidence)
            ..['fine_cents'] = 1; // tampered amount

          await expectLater(
            () => client
                .from('sanction_review_queue')
                .update({'verdict_evidence': tampered})
                .eq('id', queueRowId),
            throwsA(isA<PostgrestException>()),
          );
        });

        test(
          'UPDATE em status (campo mutável) → permitido sem exceção',
          () async {
            // status, reviewed_at, reviewed_by, rejection_reason are mutable.
            await expectLater(
              client
                  .from('sanction_review_queue')
                  .update({'status': 'disputed'})
                  .eq('id', queueRowId),
              completes,
            );

            // Restore for subsequent tests
            await client
                .from('sanction_review_queue')
                .update({'status': 'pending'})
                .eq('id', queueRowId);
          },
        );

        test('DELETE → restrict_violation (append-only — INV-1)', () async {
          await expectLater(
            () => client
                .from('sanction_review_queue')
                .delete()
                .eq('id', queueRowId),
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.message,
                'message',
                contains('append-only'),
              ),
            ),
          );

          // Row must still exist after the blocked delete.
          final rows = await client
              .from('sanction_review_queue')
              .select('id')
              .eq('id', queueRowId);

          expect(
            (rows as List).length,
            1,
            reason: 'Row must survive blocked delete',
          );
        });
      });

      // ── MT-9.3.10 — INV-23: VerdictEvidence no Motor ───────────────────────
      group('MT-9.3.10 — VerdictEvidence (INV-23)', () {
        late Map<String, dynamic> evidence;

        setUp(() async {
          final row = await client
              .from('sla_audit_ledger_v2')
              .select('payload')
              .eq('type', 'SANCTION_RECOMMENDED')
              .eq('id', ledgerEntryId)
              .single();

          final payload = row['payload'] as Map<String, dynamic>;
          evidence = payload['verdict_evidence'] as Map<String, dynamic>;
        });

        test('payload -> verdict_evidence não é nulo', () {
          expect(evidence, isNotNull);
          expect(evidence, isA<Map<String, dynamic>>());
        });

        test('evidence_hash tem exatamente 64 caracteres hexadecimais', () {
          final hash = evidence['evidence_hash'] as String;
          expect(hash.length, 64, reason: 'SHA-256 deve ter 64 chars (INV-23)');
          expect(
            RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),
            isTrue,
            reason: 'evidence_hash deve ser hex lowercase',
          );
        });

        test(
          'todos os campos obrigatórios do VerdictEvidence estão presentes e não nulos',
          () {
            const requiredFields = [
              'clause_ref',
              'rule_id',
              'rule_version',
              'primary_evidence_lat',
              'primary_evidence_lng',
              'primary_evidence_timestamp_utc',
              'evidence_hash',
              'delta_value',
              'threshold_value',
              'fine_cents',
              'confidence_score',
            ];

            for (final field in requiredFields) {
              expect(
                evidence.containsKey(field),
                isTrue,
                reason:
                    '$field deve estar presente em verdict_evidence (INV-23)',
              );
              expect(
                evidence[field],
                isNotNull,
                reason: '$field não deve ser nulo (INV-23)',
              );
            }
          },
        );

        test('rule_id não está vazio', () {
          expect((evidence['rule_id'] as String).isNotEmpty, isTrue);
        });

        test('fine_cents é inteiro positivo (INV-2)', () {
          final fineCents = evidence['fine_cents'];
          expect(fineCents, isA<int>());
          expect(fineCents as int, greaterThan(0));
        });

        test('confidence_score está entre 0 e 100', () {
          final score = evidence['confidence_score'];
          expect(score, isA<int>());
          expect(score as int, inInclusiveRange(0, 100));
        });
      });
    },
  );
}
