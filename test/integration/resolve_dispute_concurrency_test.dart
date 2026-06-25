// Concurrency / atomicity proof for the `resolve_dispute` transactional RPC.
//
// Step-2 proof-of-failure (TDD): two auditors resolve the SAME disputed sanction
// simultaneously. Without DB-side concurrency control the legacy flow appends
// TWO resolution facts to the append-only ledger (INV-3 corruption). With the
// `resolve_dispute` SECURITY DEFINER RPC (FOR UPDATE row lock + status re-check)
// exactly one caller wins and the loser observes IdempotencyProcessingException.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/resolve_dispute_concurrency_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
//
// Invariants covered:
//   INV-3  — exactly one resolution fact in the append-only ledger
//   INV-1/INV-22 — RPC re-asserts org from JWT (authenticated AUDITOR session)
//   INV-10 — concurrent loser maps to IdempotencyProcessingException
//   INV-DB — DB-enforced atomic transition (no partial state)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_dispute_resolution_repository.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _auditorEmail = 'resolve_dispute_auditor@veraprob.test';
const _auditorPassword = 'TestPassword123!';
const _orgId = PostgresTestConfig.testOrgId;

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

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient seed;
  late final SupabaseClient auditor;

  setUpAll(() async {
    if (!isRunning) return;
    seed = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
    await PostgresTestConfig.ensureSentinelOrg(client: seed);

    final auditorId = await _ensureUser(_auditorEmail, _auditorPassword);
    await seed.from('user_roles').upsert({
      'user_id': auditorId,
      'organization_id': _orgId,
      'role': 'AUDITOR',
    }, onConflict: 'user_id');

    auditor = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.supabaseAnonKey,
    );
    await auditor.auth.signInWithPassword(
      email: _auditorEmail,
      password: _auditorPassword,
    );
  });

  group('resolve_dispute — concurrency & atomicity', skip: isRunning ? null : skipReason, () {
    test(
      'two concurrent resolutions → exactly 1 success + 1 idempotency, 1 ledger fact',
      () async {
        final contractId = _uuid.v4();
        final setId = _uuid.v4();
        final evidence = {
          'clause_ref': 'rule-conc-001',
          'rule_id': 'rule-conc-001',
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

        // Contracts row required: ledger FK (sla_audit_ledger_v2.contract_id → contracts.id).
        await seed.from('contracts').upsert({
          'id': contractId,
          'organization_id': _orgId,
          'name': 'Resolve Dispute Concurrency Contract',
          'contractor_name': 'Resolve Carrier',
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

        // 1. SANCTION_RECOMMENDED ledger → trigger auto-creates a pending queue row.
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

        // 2. Drive the card to `disputed` (the only status resolve_dispute accepts).
        await seed
            .from('sanction_review_queue')
            .update({'status': 'disputed'})
            .eq('id', queueId)
            .eq('organization_id', _orgId);

        // SANCTION_DISPUTED forensic fact (realistic lineage).
        await seed.from('sla_audit_ledger_v2').insert({
          'organization_id': _orgId,
          'type': 'SANCTION_DISPUTED',
          'set_id': setId,
          'contract_id': contractId,
          'plan_version': 1,
          'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
          'payload': {'queue_entry_id': queueId, 'verdict_evidence': evidence},
        });

        // 3. Fire two identical resolutions concurrently via the AUTHENTICATED
        //    auditor session (Max hardening: RPC rejects NULL-JWT/service_role).
        final repo = PostgresSanctionDisputeResolutionRepository(auditor);
        Future<Object> attempt() => repo
            .resolveDispute(
              organizationId: _orgId,
              queueEntryId: queueId,
              resolution: 'DISPUTE_ACCEPTED',
              resolutionReason: 'Justification accepted by auditor council.',
              reasonCode: 'THIRD_PARTY_INCIDENT',
              resolvedByUserId: _uuid.v4(),
              actorEmail: _auditorEmail,
              occurredAtUtc: DateTime.now().toUtc(),
              idempotencyKey: '$queueId:DISPUTE_ACCEPTED:SNAPSHOT',
            )
            .then<Object>((r) => r)
            .catchError((Object e) => e);

        final outcomes = await Future.wait([attempt(), attempt()]);

        final successes = outcomes
            .whereType<DisputeResolutionResult>()
            .toList();
        final idempotency = outcomes
            .whereType<IdempotencyProcessingException>()
            .toList();
        print('OUTCOMES: $outcomes');

        expect(
          successes.length,
          1,
          reason: 'Exactly one caller must win the row lock.',
        );
        expect(
          idempotency.length,
          1,
          reason: 'The loser must observe IdempotencyProcessingException.',
        );
        expect(successes.first.finalQueueStatus, 'rejected');

        // 4. INV-3: exactly ONE resolution fact in the append-only ledger.
        final facts = await seed
            .from('sla_audit_ledger_v2')
            .select('id')
            .eq('organization_id', _orgId)
            .eq('type', 'DISPUTE_ACCEPTED')
            .filter('payload->>queue_entry_id', 'eq', queueId);
        expect(
          (facts as List).length,
          1,
          reason: 'Append-only ledger must hold exactly one resolution fact.',
        );

        // 5. Final queue state is the committed transition.
        final finalRow = await seed
            .from('sanction_review_queue')
            .select('status')
            .eq('id', queueId)
            .single();
        expect(finalRow['status'], 'rejected');
      },
    );
  });

  tearDownAll(() async {
    if (!isRunning) return;
    await auditor.auth.signOut();
  });
}
