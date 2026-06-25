// Concurrency / atomicity proof for the `approve_sanction` SECURITY DEFINER RPC.
//
// Pacote 1 (Transactional Hardening) migrated the legacy non-atomic Dart trail
// (READ status → CHECK pending → APPEND ledger → UPDATE queue, two round-trips)
// to a single RPC transaction. The headline claim is: two auditors approving the
// SAME pending sanction in parallel can no longer both pass the `pending` check
// and write TWO `VERDICT_SEALED` facts. pgTAP runs single-session and cannot
// prove this. This test drives the real race: TWO distinct authenticated auditors
// approve the SAME pending entry simultaneously. The RPC's `FOR UPDATE` row lock +
// status re-check (`<> 'pending'`) must let exactly ONE win and seal, while the
// loser observes IdempotencyProcessingException — never a second seal.
//
// The contract carries a HIGH dual-control threshold so the verdict seals TERMINAL
// (no four-eyes fork) — this isolates the approve TOCTOU race from dual-control.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/approve_sanction_concurrency_test.dart
//
// Invariants covered:
//   INV-3  — exactly one terminal verdict fact in the append-only ledger
//   INV-1/INV-22 — RPC re-asserts org + identity from JWT (authenticated AUDITOR)
//   INV-10 — concurrent loser maps to IdempotencyProcessingException
//   INV-DB — DB-enforced atomic transition (no partial state, no double-seal)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_review_command_repository.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _password = 'TestPassword123!';
const _orgId = PostgresTestConfig.testOrgId;

const _approverAEmail = 'approve_race_auditor_a@veraprob.test';
const _approverBEmail = 'approve_race_auditor_b@veraprob.test';

Future<String> _ensureUser(String email, String password) async {
  final res = await http.post(
    Uri.parse('${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users'),
    headers: {
      'apikey': PostgresTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );
  if (res.statusCode == 200 || res.statusCode == 201) {
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }
  if (res.statusCode == 422) {
    final list = await http.get(
      Uri.parse(
        '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users?email=$email',
      ),
      headers: {
        'apikey': PostgresTestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      },
    );
    final users =
        (jsonDecode(list.body) as Map<String, dynamic>)['users'] as List?;
    return (users!.first as Map<String, dynamic>)['id'] as String;
  }
  throw Exception('createUser failed (${res.statusCode}): ${res.body}');
}

Future<SupabaseClient> _signIn(String email) async {
  final client = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.supabaseAnonKey,
  );
  await client.auth.signInWithPassword(email: email, password: _password);
  return client;
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient seed;
  late final SupabaseClient approverA;
  late final SupabaseClient approverB;
  late final String approverAId;
  late final String approverBId;

  setUpAll(() async {
    if (!isRunning) return;
    seed = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
    await PostgresTestConfig.ensureSentinelOrg(client: seed);

    approverAId = await _ensureUser(_approverAEmail, _password);
    approverBId = await _ensureUser(_approverBEmail, _password);

    for (final id in [approverAId, approverBId]) {
      await seed.from('user_roles').upsert({
        'user_id': id,
        'organization_id': _orgId,
        'role': 'AUDITOR',
      }, onConflict: 'user_id');
    }

    approverA = await _signIn(_approverAEmail);
    approverB = await _signIn(_approverBEmail);
  });

  group(
    'approve_sanction — TOCTOU concurrency & atomicity',
    skip: isRunning ? null : skipReason,
    () {
      test(
        'two auditors approve same pending sanction → exactly 1 seal + 1 idempotency, 1 ledger fact',
        () async {
          final contractId = _uuid.v4();
          final setId = _uuid.v4();
          final evidence = {
            'clause_ref': 'rule-approve-conc-001',
            'rule_id': 'rule-approve-conc-001',
            'rule_version': 1,
            'primary_evidence_lat': -23.5505,
            'primary_evidence_lng': -46.6333,
            'primary_evidence_timestamp_utc': '2026-06-09T10:00:00.000Z',
            'evidence_hash': 'a' * 64,
            'delta_value': 15.0,
            'threshold_value': 0.0,
            'fine_cents': 150000,
            'confidence_score': 100,
          };

          // HIGH contract threshold (> 150000 fine) so approve seals TERMINAL
          // and never forks into peer review — isolates the TOCTOU race.
          await seed.from('contracts').upsert({
            'id': contractId,
            'organization_id': _orgId,
            'name': 'Approve Concurrency Contract',
            'contractor_name': 'Approve Carrier',
            'valid_from_utc': '2026-01-01T00:00:00Z',
            'valid_until_utc': '2027-01-01T00:00:00Z',
            'status': 'active',
            'dual_control_threshold_cents': 100000000,
          }, onConflict: 'organization_id,name,valid_from_utc');

          // Seed mandatory forensic rule definitions. Without these, `_persist_evidence_snapshot`
          // will correctly throw a P0002 (Hard-Fail) to prevent un-sealable verdicts.
          final ruleSetId = _uuid.v4();
          await seed.from('contract_rule_sets').insert({
            'id': ruleSetId,
            'organization_id': _orgId,
            'contract_id': contractId,
          });
          await seed.from('contract_rule_versions').insert({
            'id': _uuid.v4(),
            'rule_set_id': ruleSetId,
            'rule_type': 'MAX_TOLERANCE_DELAY',
            'rule_config': {'threshold_minutes': 15},
            'rule_version': 1,
            'evaluation_order': 1,
            'created_at_utc': '2026-01-01T00:00:00Z',
            'active_from_utc': '2026-01-01T00:00:00Z',
          });

          // SANCTION_RECOMMENDED ledger → trigger auto-creates a pending queue row.
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
          final recommendedId = recommended['id'] as String;

          await Future<void>.delayed(const Duration(milliseconds: 300));
          final queueRow = await seed
              .from('sanction_review_queue')
              .select('id')
              .eq('ledger_entry_id', recommendedId)
              .single();
          final queueId = queueRow['id'] as String;

          // Two DISTINCT auditors approve the SAME pending entry concurrently.
          // Both pass the client-side guards; the DB row lock must serialise them.
          final repoA = PostgresSanctionReviewCommandRepository(approverA);
          final repoB = PostgresSanctionReviewCommandRepository(approverB);
          Future<Object> attempt(
            PostgresSanctionReviewCommandRepository repo,
            String userId,
            String email,
          ) => repo
              .approveSanction(
                organizationId: _orgId,
                queueEntryId: queueId,
                reviewedByUserId: userId,
                actorEmail: email,
                occurredAtUtc: DateTime.now().toUtc(),
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e);

          final jwtA = approverA.auth.currentSession?.accessToken;
          if (jwtA != null) {
            final payload = utf8.decode(
              base64Url.decode(base64Url.normalize(jwtA.split('.')[1])),
            );
            print('JWT A PAYLOAD: $payload');
          }
          final outcomes = await Future.wait([
            attempt(repoA, approverAId, _approverAEmail),
            attempt(repoB, approverBId, _approverBEmail),
          ]);
          final successes = outcomes.whereType<SanctionReviewResult>().toList();
          final idempotency = outcomes
              .whereType<IdempotencyProcessingException>()
              .toList();
          print('OUTCOMES: $outcomes');

          expect(
            successes.length,
            1,
            reason: 'Exactly one approver must win the row lock.',
          );
          expect(
            idempotency.length,
            1,
            reason: 'The loser must observe IdempotencyProcessingException.',
          );
          expect(successes.first.finalQueueStatus, 'applied');

          // INV-3: exactly ONE terminal verdict fact (no double-seal).
          final facts = await seed
              .from('sla_audit_ledger_v2')
              .select('id, payload')
              .eq('organization_id', _orgId)
              .eq('type', 'VERDICT_SEALED')
              .filter('payload->>queue_entry_id', 'eq', queueId);
          expect(
            (facts as List).length,
            1,
            reason: 'Append-only ledger must hold exactly one terminal fact.',
          );

          // The seal records the winning approver (one of the two racers).
          final sealPayload = facts.first['payload'] as Map<String, dynamic>;
          expect([
            approverAId,
            approverBId,
          ], contains(sealPayload['approved_by_user_id']));

          // Final queue state is the committed terminal transition.
          final finalRow = await seed
              .from('sanction_review_queue')
              .select('status')
              .eq('id', queueId)
              .single();
          expect(finalRow['status'], 'applied');
        },
      );
    },
  );

  tearDownAll(() async {
    if (!isRunning) return;
    await approverA.auth.signOut();
    await approverB.auth.signOut();
  });
}
