// Concurrency / atomicity proofs for the Sprint A portal counter-evidence and
// "De Acordo" (acknowledgement) RPCs. dblink self-connect is blocked in the
// local Supabase stack (postgres is not superuser), so true parallelism is
// achieved with N independent SupabaseClient instances fired via Future.wait —
// each call lands on its own DB connection, and the in-RPC advisory locks are
// what must serialize them.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/portal_evidence_concurrency_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
//
// Invariants covered:
//   INV-3  — append-only ledger / single attachment / single acknowledgement
//   INV-9  — server-sealed evidence (register is idempotent on replay)
//   INV-22 — per-token availability ceiling enforced race-free
//   INV-DB — DB-enforced atomic transitions (no partial / duplicate state)

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _orgId = PostgresTestConfig.testOrgId;

Future<({String queueId, String setId, String contractId})> _disputedQueue(
  SupabaseClient seed,
) async {
  final setId = _uuid.v4();
  final contractId = _uuid.v4();
  final evidence = {
    'clause_ref': 'rule-portal-conc',
    'rule_id': 'rule-portal-conc',
    'rule_version': 1,
    'primary_evidence_lat': -23.5505,
    'primary_evidence_lng': -46.6333,
    'primary_evidence_timestamp_utc': '2026-06-09T10:00:00.000Z',
    'evidence_hash': 'c' * 64,
    'delta_value': 15.0,
    'threshold_value': 0.0,
    'fine_cents': 150000,
    'confidence_score': 100,
  };

  final recommended = await seed
      .from('sla_audit_ledger_v2')
      .insert({
        'organization_id': _orgId,
        'type': 'SANCTION_RECOMMENDED',
        'set_id': setId,
        'contract_id': contractId,
        'plan_version': 1,
        'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
        'payload': {'verdict_evidence': evidence},
      })
      .select('id')
      .single();

  await Future<void>.delayed(const Duration(milliseconds: 300));
  final queueRow = await seed
      .from('sanction_review_queue')
      .select('id')
      .eq('ledger_entry_id', recommended['id'] as String)
      .single();
  final queueId = queueRow['id'] as String;

  await seed
      .from('sanction_review_queue')
      .update({'status': 'disputed'})
      .eq('id', queueId)
      .eq('organization_id', _orgId);

  return (queueId: queueId, setId: setId, contractId: contractId);
}

Future<({String id, String token})> _insertToken(
  SupabaseClient seed, {
  required String queueId,
  required String scope,
  int maxSubmissions = 5,
}) async {
  final now = DateTime.now().toUtc();
  final row = await seed
      .from('dispute_portal_tokens')
      .insert({
        'organization_id': _orgId,
        'queue_entry_id': queueId,
        'created_by_user_id': _uuid.v4(),
        'token_scope': scope,
        'max_submissions': maxSubmissions,
        'max_access_count': 50,
        'created_at_utc': now.toIso8601String(),
        'expires_at_utc': now.add(const Duration(hours: 24)).toIso8601String(),
      })
      .select('id, token')
      .single();
  return (id: row['id'] as String, token: row['token'] as String);
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient seed;

  setUpAll(() async {
    if (!isRunning) return;
    seed = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
    await PostgresTestConfig.ensureSentinelOrg(client: seed);
  });

  group(
    'portal counter-evidence & De Acordo — concurrency & atomicity',
    skip: isRunning ? null : skipReason,
    () {
      test(
        'AT-06: 6 parallel submissions under cap=5 → exactly 5 succeed, 1 rejected',
        () async {
          final q = await _disputedQueue(seed);
          final tok = await _insertToken(
            seed,
            queueId: q.queueId,
            scope: 'submit',
            maxSubmissions: 5,
          );

          // Six independent clients → six independent DB connections.
          final clients = List.generate(
            6,
            (_) => SupabaseClient(
              PostgresTestConfig.supabaseUrl,
              PostgresTestConfig.serviceRoleKey,
            ),
          );

          // DISTINCT sha per client: hash idempotency dedups identical bytes
          // BEFORE the cap check, so identical shas would collapse to one row.
          // The availability ceiling is what this test proves — keep the bytes
          // distinct so all six are genuine, competing submissions.
          Future<Object> attempt(SupabaseClient c, int i) => c
              .rpc<List<dynamic>>(
                'create_portal_submission',
                params: {
                  'p_token': tok.token,
                  'p_file_name': 'evidence.pdf',
                  'p_mime_type': 'application/pdf',
                  'p_file_size_bytes': 1024,
                  'p_sha256_client': i.toString().padLeft(64, '0'),
                  'p_justification':
                      'Justificativa de contestacao para o teste de concorrencia.',
                },
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e);

          final outcomes = await Future.wait(<Future<Object>>[
            for (var i = 0; i < clients.length; i++) attempt(clients[i], i),
          ]);
          for (final c in clients) {
            await c.dispose();
          }

          final successes = outcomes
              .where((o) => o is List && o.isNotEmpty)
              .length;
          final rejections = outcomes.whereType<PostgrestException>().length;

          expect(
            successes,
            5,
            reason: 'Per-token cap=5 must admit exactly five submissions.',
          );
          expect(
            rejections,
            1,
            reason:
                'The 6th submission must be rejected (availability ceiling).',
          );

          final rows = await seed
              .from('portal_evidence_submissions')
              .select('id')
              .eq('token_id', tok.id);
          expect(
            (rows as List).length,
            5,
            reason: 'Exactly five quarantine rows persisted for the token.',
          );
        },
      );

      test(
        'AT-07: 2 parallel submits, same (token, sha) → 1 quarantine row, same submission_id',
        () async {
          final q = await _disputedQueue(seed);
          final tok = await _insertToken(
            seed,
            queueId: q.queueId,
            scope: 'submit',
            maxSubmissions: 5,
          );

          final clients = List.generate(
            2,
            (_) => SupabaseClient(
              PostgresTestConfig.supabaseUrl,
              PostgresTestConfig.serviceRoleKey,
            ),
          );

          // Identical bytes → hash idempotency must collapse both calls onto the
          // SAME quarantine row (no second slot consumed) under the advisory lock.
          final sha = 'a' * 64;
          Future<Object> submit(SupabaseClient c) => c
              .rpc<List<dynamic>>(
                'create_portal_submission',
                params: {
                  'p_token': tok.token,
                  'p_file_name': 'evidence.pdf',
                  'p_mime_type': 'application/pdf',
                  'p_file_size_bytes': 1024,
                  'p_sha256_client': sha,
                  'p_justification':
                      'Justificativa de contestacao para o teste de idempotencia.',
                },
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e);

          final outcomes = await Future.wait(clients.map(submit));
          for (final c in clients) {
            await c.dispose();
          }

          final ids = outcomes
              .where((o) => o is List && o.isNotEmpty)
              .map(
                (o) =>
                    ((o as List).first as Map<String, dynamic>)['submission_id']
                        as String,
              )
              .toSet();
          expect(
            ids.length,
            1,
            reason: 'Idempotent submit must return the one same submission id.',
          );

          final rows = await seed
              .from('portal_evidence_submissions')
              .select('id')
              .eq('token_id', tok.id);
          expect(
            (rows as List).length,
            1,
            reason: 'Exactly one quarantine row for identical (token, sha).',
          );
        },
      );

      test(
        'AT-08: 2 parallel register_portal_evidence → 1 attachment, same id (idempotent)',
        () async {
          final q = await _disputedQueue(seed);
          final tok = await _insertToken(
            seed,
            queueId: q.queueId,
            scope: 'submit',
          );

          final minted = await seed.rpc<List<dynamic>>(
            'create_portal_submission',
            params: {
              'p_token': tok.token,
              'p_file_name': 'evidence.png',
              'p_mime_type': 'image/png',
              'p_file_size_bytes': 2048,
              'p_sha256_client': 'e' * 64,
              'p_justification':
                  'Justificativa de contestacao para o teste de idempotencia.',
            },
          );
          final submissionId =
              (minted.first as Map<String, dynamic>)['submission_id'] as String;

          final clients = List.generate(
            2,
            (_) => SupabaseClient(
              PostgresTestConfig.supabaseUrl,
              PostgresTestConfig.serviceRoleKey,
            ),
          );

          Future<Object> register(SupabaseClient c) => c
              .rpc<dynamic>(
                'register_portal_evidence',
                params: {
                  'p_submission_id': submissionId,
                  'p_sha256_server': 'e' * 64,
                  'p_mime_type_detected': 'image/png',
                  'p_file_size_bytes_actual': 2048,
                },
              )
              .then<Object>((r) => r as Object)
              .catchError((Object e) => e);

          final outcomes = await Future.wait(clients.map(register));
          for (final c in clients) {
            await c.dispose();
          }

          final ids = outcomes.whereType<String>().toSet();
          expect(
            ids.length,
            1,
            reason: 'Idempotent replay must return the one same attachment id.',
          );

          final rows = await seed
              .from('dispute_evidence_attachments')
              .select('id')
              .eq('queue_entry_id', q.queueId)
              .eq('submission_id', submissionId);
          expect(
            (rows as List).length,
            1,
            reason: 'Exactly one attachment for the finalized submission.',
          );
        },
      );

      test(
        'ack: 2 parallel acknowledge_via_portal → 1 acknowledgement, same id (idempotent)',
        () async {
          final q = await _disputedQueue(seed);
          // De Acordo is only meaningful once the sanction is applied.
          await seed
              .from('sanction_review_queue')
              .update({'status': 'applied'})
              .eq('id', q.queueId)
              .eq('organization_id', _orgId);

          final tok = await _insertToken(
            seed,
            queueId: q.queueId,
            scope: 'read',
          );

          final snapshotHash = 'd' * 64;
          // Hash binding: the served snapshot recorded at first portal access.
          await seed.from('sla_audit_ledger_v2').insert({
            'organization_id': _orgId,
            'type': 'DISPUTE_PORTAL_TOKEN_ACCESSED',
            'set_id': q.setId,
            'contract_id': q.contractId,
            'plan_version': 0,
            'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
            'payload': {'token_id': tok.id, 'snapshot_hash': snapshotHash},
          });

          // anon clients: acknowledge_via_portal is granted to anon/authenticated.
          final clients = List.generate(
            2,
            (_) => SupabaseClient(
              PostgresTestConfig.supabaseUrl,
              PostgresTestConfig.supabaseAnonKey,
            ),
          );

          Future<Object> ack(SupabaseClient c) => c
              .rpc<dynamic>(
                'acknowledge_via_portal',
                params: {'p_token': tok.token, 'p_snapshot_hash': snapshotHash},
              )
              .then<Object>((r) => r as Object)
              .catchError((Object e) => e);

          final outcomes = await Future.wait(clients.map(ack));
          for (final c in clients) {
            await c.dispose();
          }

          final ids = outcomes.whereType<String>().toSet();
          expect(
            ids.length,
            1,
            reason:
                'Idempotent ack must return the one same acknowledgement id.',
          );

          final rows = await seed
              .from('sanction_acknowledgements')
              .select('id')
              .eq('queue_entry_id', q.queueId);
          expect(
            (rows as List).length,
            1,
            reason:
                'Exactly one acknowledgement persisted for the queue entry.',
          );

          final finalRow = await seed
              .from('sanction_review_queue')
              .select('status')
              .eq('id', q.queueId)
              .single();
          expect(finalRow['status'], 'acknowledged');
        },
      );
    },
  );

  tearDownAll(() async {
    if (!isRunning) return;
    await seed.dispose();
  });
}
