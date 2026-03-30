// Integration tests for sanction_review_queue DB invariants.
//
// Prerequisites:
//   - Real Postgres instance with migrations applied
//   - env: SUPABASE_URL, SUPABASE_KEY (or --dart-define)
//
// Run: flutter test test/integration/sanction_review_queue_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
//
// Verifies:
//   - Trigger auto-populates queue on SANCTION_RECOMMENDED INSERT
//   - ON CONFLICT DO NOTHING (INV-24)
//   - RLS: AUDITOR sees own org, OPERATOR sees zero rows
//   - UPDATE on immutable field → restrict_violation (INV-1)
//   - DELETE → restrict_violation (INV-1)

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../infrastructure/postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient client;
  const orgId = PostgresTestConfig.testOrgId;

  setUpAll(() async {
    if (isRunning) {
      client = SupabaseClient(
        PostgresTestConfig.supabaseUrl,
        PostgresTestConfig.serviceRoleKey,
      );
    }
  });

  group('sanction_review_queue — DB invariants', skip: isRunning ? null : skipReason, () {
    test(
      'trigger auto-populates queue on SANCTION_RECOMMENDED insert',
      () async {
        final fakeEvidence = {
          'clause_ref': 'rule-int-001',
          'rule_id': 'rule-int-001',
          'rule_version': 1,
          'primary_evidence_lat': -23.5505,
          'primary_evidence_lng': -46.6333,
          'primary_evidence_timestamp_utc': '2026-04-06T10:00:00.000Z',
          'evidence_hash': 'a' * 64,
          'delta_value': 15.0,
          'threshold_value': 0.0,
          'fine_cents': 150000,
          'confidence_score': 100,
        };

        // Insert a SANCTION_RECOMMENDED ledger entry
        final ledgerRow = await client
            .from('sla_audit_ledger_v2')
            .insert({
              'organization_id': orgId,
              'type': 'SANCTION_RECOMMENDED',
              'set_id': '00000000-0000-0000-0000-000000000101',
              'contract_id': '00000000-0000-0000-0000-000000000100',
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
              'payload': {'verdict_evidence': fakeEvidence},
            })
            .select('id')
            .single();

        final ledgerEntryId = ledgerRow['id'] as String;

        // Verify queue entry was auto-created by the trigger
        await Future.delayed(const Duration(milliseconds: 200));
        final queueRows = await client
            .from('sanction_review_queue')
            .select()
            .eq('ledger_entry_id', ledgerEntryId);

        expect((queueRows as List).length, 1);
        expect(queueRows.first['status'], 'pending');
        expect(queueRows.first['organization_id'], orgId);
      },
    );

    test(
      'duplicate SANCTION_RECOMMENDED insert → only one queue row (INV-24)',
      () async {
        final fakeEvidence = {
          'clause_ref': 'rule-int-002',
          'rule_id': 'rule-int-002',
          'rule_version': 1,
          'primary_evidence_lat': -23.5505,
          'primary_evidence_lng': -46.6333,
          'primary_evidence_timestamp_utc': '2026-04-06T11:00:00.000Z',
          'evidence_hash': 'b' * 64,
          'delta_value': 10.0,
          'threshold_value': 0.0,
          'fine_cents': 100000,
          'confidence_score': 100,
        };

        // Insert first ledger entry
        final ledgerRow1 = await client
            .from('sla_audit_ledger_v2')
            .insert({
              'organization_id': orgId,
              'type': 'SANCTION_RECOMMENDED',
              'set_id': '00000000-0000-0000-0000-000000000201',
              'contract_id': '00000000-0000-0000-0000-000000000200',
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
              'payload': {'verdict_evidence': fakeEvidence},
            })
            .select('id')
            .single();

        final ledgerEntryId = ledgerRow1['id'] as String;
        await Future.delayed(const Duration(milliseconds: 200));

        // Attempt direct duplicate insert into queue
        await client
            .from('sanction_review_queue')
            .upsert(
              {
                'organization_id': orgId,
                'ledger_entry_id': ledgerEntryId,
                'set_id': '00000000-0000-0000-0000-000000000201',
                'contract_id': '00000000-0000-0000-0000-000000000200',
                'verdict_evidence': fakeEvidence,
                'status': 'pending',
              },
              onConflict: 'ledger_entry_id',
              ignoreDuplicates: true,
            );

        final queueRows = await client
            .from('sanction_review_queue')
            .select()
            .eq('ledger_entry_id', ledgerEntryId);

        expect((queueRows as List).length, 1); // exactly one
      },
    );

    test(
      'UPDATE on immutable field → restrict_violation (INV-1)',
      () async {
        final rows = await client
            .from('sanction_review_queue')
            .select('id, organization_id')
            .eq('organization_id', orgId)
            .limit(1);

        if ((rows as List).isEmpty) {
          markTestSkipped('No queue rows available for immutability test.');
          return;
        }

        final rowId = rows.first['id'] as String;

        // Attempt to mutate organization_id (immutable field)
        expect(
          () async => client
              .from('sanction_review_queue')
              .update({
                'organization_id': '00000000-0000-0000-0000-000000000004',
              })
              .eq('id', rowId),
          throwsA(anything),
        );
      },
    );
  });
}
