// Concurrency / atomicity proof for the `confirm_peer_review` dual-control RPC.
//
// The anti-fraud loop forks a high-value verdict into `pending_peer_review` and
// requires a SECOND, DISTINCT auditor to confirm. This test drives the real race
// the single-session pgTAP suite cannot: TWO distinct authenticated auditors
// confirm the SAME forked verdict simultaneously. The RPC's `FOR UPDATE` row lock
// + status re-check (`<> 'pending_peer_review'`) must let exactly ONE win and seal,
// while the loser observes IdempotencyProcessingException — never a second seal.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/dual_control_confirm_concurrency_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
//
// Invariants covered:
//   INV-3  — exactly one terminal verdict fact in the append-only ledger
//   INV-1/INV-22 — RPC re-asserts org + identity from JWT (authenticated AUDITOR)
//   INV-10 — concurrent loser maps to IdempotencyProcessingException
//   INV-DB — DB-enforced atomic transition (no partial state, no double-seal)
//   Dual-control — both confirmers are distinct from the first reviewer; the race
//                  is between two legitimate second auditors.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_review_command_repository.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _password = 'TestPassword123!';
const _orgId = PostgresTestConfig.testOrgId;

const _reviewer1Email = 'dc_confirm_reviewer1@veraprob.test';
const _confirmerAEmail = 'dc_confirm_auditor_a@veraprob.test';
const _confirmerBEmail = 'dc_confirm_auditor_b@veraprob.test';

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
  late final SupabaseClient reviewer1;
  late final SupabaseClient confirmerA;
  late final SupabaseClient confirmerB;
  late final String reviewer1Id;
  late final String confirmerAId;
  late final String confirmerBId;

  setUpAll(() async {
    if (!isRunning) return;
    seed = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
    await PostgresTestConfig.ensureSentinelOrg(client: seed);

    reviewer1Id = await PostgresTestConfig.ensureUser(
      email: _reviewer1Email,
      password: _password,
    );
    confirmerAId = await PostgresTestConfig.ensureUser(
      email: _confirmerAEmail,
      password: _password,
    );
    confirmerBId = await PostgresTestConfig.ensureUser(
      email: _confirmerBEmail,
      password: _password,
    );

    for (final id in [reviewer1Id, confirmerAId, confirmerBId]) {
      await seed.from('user_roles').upsert({
        'user_id': id,
        'organization_id': _orgId,
        'role': 'AUDITOR',
      }, onConflict: 'user_id');
    }

    reviewer1 = await _signIn(_reviewer1Email);
    confirmerA = await _signIn(_confirmerAEmail);
    confirmerB = await _signIn(_confirmerBEmail);
  });

  group(
    'confirm_peer_review — dual-control concurrency & atomicity',
    skip: isRunning ? null : skipReason,
    () {
      test(
        'two distinct confirmers race → exactly 1 seal + 1 idempotency, 1 ledger fact',
        () async {
          final contractId = _uuid.v4();
          final setId = _uuid.v4();
          final evidence = {
            'clause_ref': 'rule-dc-conc-001',
            'rule_id': 'rule-dc-conc-001',
            'rule_version': 1,
            'primary_evidence_lat': -23.5505,
            'primary_evidence_lng': -46.6333,
            'primary_evidence_timestamp_utc': '2026-06-09T10:00:00.000Z',
            'evidence_hash': 'd' * 64,
            'delta_value': 15.0,
            'threshold_value': 0.0,
            'fine_cents': 150000,
            'confidence_score': 100,
          };

          // Contract-level threshold override (10000 < 150000 fine) so the verdict
          // forks WITHOUT touching the org baseline — no cross-test pollution.
          await seed.from('contracts').upsert({
            'id': contractId,
            'organization_id': _orgId,
            'name': 'DC Concurrency Contract',
            'contractor_name': 'DC Carrier',
            'valid_from_utc': '2026-01-01T00:00:00Z',
            'valid_until_utc': '2027-01-01T00:00:00Z',
            'status': 'active',
            'dual_control_threshold_cents': 10000,
          }, onConflict: 'organization_id,name,valid_from_utc');

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

          // 2. First reviewer approves → forks into pending_peer_review (above
          //    the contract threshold). first_reviewer_id = reviewer1 (JWT sub).
          final reviewer1Repo = PostgresSanctionReviewCommandRepository(
            reviewer1,
          );
          final fork = await reviewer1Repo.approveSanction(
            organizationId: _orgId,
            queueEntryId: queueId,
            reviewedByUserId: reviewer1Id,
            actorEmail: _reviewer1Email,
            occurredAtUtc: DateTime.now().toUtc(),
          );
          expect(
            fork.finalQueueStatus,
            'pending_peer_review',
            reason: 'High-value approve must fork, not seal.',
          );

          // 3. Two DISTINCT second auditors confirm concurrently. Both are valid
          //    (≠ reviewer1); the row lock must serialise them.
          final repoA = PostgresSanctionReviewCommandRepository(confirmerA);
          final repoB = PostgresSanctionReviewCommandRepository(confirmerB);
          Future<Object> attempt(
            PostgresSanctionReviewCommandRepository repo,
            String userId,
            String email,
          ) => repo
              .confirmPeerReview(
                organizationId: _orgId,
                queueEntryId: queueId,
                reviewedByUserId: userId,
                actorEmail: email,
                occurredAtUtc: DateTime.now().toUtc(),
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e);

          final outcomes = await Future.wait([
            attempt(repoA, confirmerAId, _confirmerAEmail),
            attempt(repoB, confirmerBId, _confirmerBEmail),
          ]);

          final successes = outcomes.whereType<SanctionReviewResult>().toList();
          final idempotency = outcomes
              .whereType<IdempotencyProcessingException>()
              .toList();

          expect(
            successes.length,
            1,
            reason: 'Exactly one confirmer must win the row lock.',
          );
          expect(
            idempotency.length,
            1,
            reason: 'The loser must observe IdempotencyProcessingException.',
          );
          expect(successes.first.finalQueueStatus, 'applied');

          // 4. INV-3: exactly ONE terminal verdict fact (no double-seal).
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

          // 5. Dual-signature trail: the single seal records BOTH reviewers, and
          //    the second reviewer is the winning confirmer (never reviewer1).
          final sealPayload = facts.first['payload'] as Map<String, dynamic>;
          expect(sealPayload['first_reviewer_id'], reviewer1Id);
          expect(
            sealPayload['second_reviewer_id'],
            isNot(reviewer1Id),
            reason: 'The confirming auditor must differ from the requester.',
          );
          expect([
            confirmerAId,
            confirmerBId,
          ], contains(sealPayload['second_reviewer_id']));

          // 6. Final queue state is the committed terminal transition.
          final finalRow = await seed
              .from('sanction_review_queue')
              .select('status, first_reviewer_id')
              .eq('id', queueId)
              .single();
          expect(finalRow['status'], 'applied');
          expect(
            finalRow['first_reviewer_id'],
            isNull,
            reason: 'Peer-review working state must be wiped after seal.',
          );
        },
      );
    },
  );

  tearDownAll(() async {
    if (!isRunning) return;
    await reviewer1.auth.signOut();
    await confirmerA.auth.signOut();
    await confirmerB.auth.signOut();
  });
}
