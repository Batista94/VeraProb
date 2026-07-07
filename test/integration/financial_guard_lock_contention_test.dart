// Lock-contention / stop-loss proof for `enforce_financial_guard()` — the
// "Tempestade de Sensores" storm. Ten billable sanctions land on the SAME
// capped contract simultaneously across three isolated PostgREST connections.
// The BEFORE-INSERT guard serialises them under `contracts FOR UPDATE`, so the
// per-contract UTC-month accrual settles EXACTLY at the cap and never exceeds
// it, regardless of arrival interleaving.
//
// service_role is deliberate: the guard's Phase A claim-check is skipped for
// service_role, but the Phase D `FOR UPDATE` serialisation runs for ANY role —
// it is that serialisation under real crossfire that is under test here.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/financial_guard_lock_contention_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
//
// Invariants covered:
//   INV-3  — append-only ledger; every fact preserved (original sealed)
//   INV-4  — BIGINT cents accrual, exact at cap
//   INV-16 — bounded-wait lock; no deferral in a healthy local environment

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _orgId = PostgresTestConfig.testOrgId;
const _cap = 50000;
const _fine = 20000;
const _shots = 10;

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient seed;
  // Three isolated HTTP stacks = three distinct PostgREST connections, so the
  // parallel inserts genuinely contend for the contracts row lock.
  late final List<SupabaseClient> shooters;

  setUpAll(() async {
    if (!isRunning) return;
    seed = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
    await PostgresTestConfig.ensureSentinelOrg(client: seed);
    shooters = List.generate(
      3,
      (_) => SupabaseClient(
        PostgresTestConfig.supabaseUrl,
        PostgresTestConfig.serviceRoleKey,
      ),
    );
  });

  group(
    'financial guard — lock contention (Tempestade de Sensores)',
    skip: isRunning ? null : skipReason,
    () {
      test('10 concurrent fines settle exactly at the cap, never above', () async {
        // Fresh contract per run → this UTC month's accrual starts at 0 with no
        // cleanup (append-only). Unique name keeps the upsert idempotent.
        final contractId = _uuid.v4();
        await seed.from('contracts').upsert({
          'id': contractId,
          'organization_id': _orgId,
          'name': 'FG Contention $contractId',
          'contractor_name': 'Storm Carrier',
          'valid_from_utc': '2026-01-01T00:00:00Z',
          'valid_until_utc': '2027-01-01T00:00:00Z',
          'status': 'active',
          'monthly_penalty_cap_cents': _cap,
        }, onConflict: 'organization_id,name,valid_from_utc');

        Future<Object> fire(int i) => shooters[i % shooters.length]
            .from('sla_audit_ledger_v2')
            .insert({
              'organization_id': _orgId,
              'type': 'SANCTION_RECOMMENDED',
              'set_id': _uuid.v4(),
              'contract_id': contractId,
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
              'payload': {
                'verdict_evidence': {'fine_cents': _fine},
              },
            })
            .then<Object>((_) => true)
            .catchError((Object e) => e);

        final outcomes = await Future.wait(List.generate(_shots, fire));

        // 1. Every insert succeeds — the guard truncates, it never rejects.
        expect(
          outcomes.where((o) => o == true).length,
          _shots,
          reason:
              'All $_shots fines must be accepted (guard cuts, not blocks).',
        );

        // Read every guarded ledger row for this contract.
        final rows =
            (await seed
                    .from('sla_audit_ledger_v2')
                    .select('payload')
                    .eq('contract_id', contractId)
                    .eq('type', 'SANCTION_RECOMMENDED'))
                as List;
        expect(rows.length, _shots);

        int applied(dynamic r) =>
            ((r['payload']['verdict_evidence']['fine_cents']) as num).toInt();
        int? original(dynamic r) =>
            (r['payload']['original_fine_cents'] as num?)?.toInt();
        bool truncated(dynamic r) => r['payload']['cap_truncated'] == true;
        bool deferred(dynamic r) => r['payload']['cap_check_deferred'] == true;

        // 3. No deferral in a healthy environment (2s lock_timeout >> real wait).
        expect(
          rows.where(deferred).length,
          0,
          reason: 'Deferral signals a pathological environment, not a pass.',
        );

        // 4. Deterministic multiset: [0×7, 10000, 20000, 20000], sum == cap.
        final effective = rows.map(applied).toList()..sort();
        expect(effective, [0, 0, 0, 0, 0, 0, 0, 10000, _fine, _fine]);
        expect(effective.reduce((a, b) => a + b), _cap);

        // 5. Eight truncated rows, each sealing the untouched original (INV-3).
        final cut = rows.where(truncated).toList();
        expect(cut.length, 8);
        for (final r in cut) {
          expect(original(r), _fine);
        }

        // 2. Accrual settles EXACTLY at the cap — the core stop-loss guarantee.
        final accrual = await seed
            .from('contract_penalty_monthly_accrual')
            .select('accrued_cents, cap_reached_at_utc')
            .eq('contract_id', contractId)
            .single();
        expect((accrual['accrued_cents'] as num).toInt(), _cap);
        expect(accrual['cap_reached_at_utc'], isNotNull);

        // 6. Exactly ONE breach fact under crossfire (idempotent latch).
        final breach =
            (await seed
                    .from('sla_audit_ledger_v2')
                    .select('id')
                    .eq('contract_id', contractId)
                    .eq('type', 'FINANCIAL_CAP_REACHED'))
                as List;
        expect(breach.length, 1);
      });
    },
  );

  tearDownAll(() async {
    if (!isRunning) return;
    for (final c in shooters) {
      await c.dispose();
    }
    await seed.dispose();
  });
}
