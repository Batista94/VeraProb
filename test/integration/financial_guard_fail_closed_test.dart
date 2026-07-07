// Concurrency test for Financial Guard fail-closed behavior (INV-16, INV-18)
//
// Proof-of-failure: Under lock contention, the guard must fail-closed,
// sealing the fine as 0 (no over-billing), marking it as deferred, and leaving
// the accrual row untouched. A subsequent reconcile call should not flag it as
// a correction since the true-up logic skips fully truncated zero-accrual cases
// if there are no other fines.
//
// Prerequisites: `supabase start` running locally.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _orgId = PostgresTestConfig.testOrgId;

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
    'enforce_financial_guard — fail-closed under lock contention',
    skip: isRunning ? null : skipReason,
    () {
      test('lock timeout seals fine as 0, defers cap check, accrual untouched', () async {
        final contractId = _uuid.v4();
        final setId = _uuid.v4();
        const fineAmount = 50000;

        // Seed contract with a cap
        await seed.from('contracts').upsert({
          'id': contractId,
          'organization_id': _orgId,
          'name': 'Fail-Closed Test Contract ${_uuid.v4()}',
          'contractor_name': 'Fail-Closed Carrier',
          'valid_from_utc': '2026-01-01T00:00:00Z',
          'valid_until_utc': '2030-01-01T00:00:00Z',
          'status': 'active',
          'monthly_penalty_cap_cents': 100000,
          'dual_control_threshold_cents': 100000000,
        });

        // We need to hold the lock in another transaction.
        // We will use Supabase RPC to call our test-only function.
        // test_hold_financial_guard_lock holds the lock for 4 seconds.
        // In parallel, we insert the SANCTION_RECOMMENDED (waits ~300ms before starting).

        final lockFuture = seed.rpc<dynamic>(
          'test_hold_financial_guard_lock',
          params: {
            'p_organization_id': _orgId,
            'p_contract_id': contractId,
            'p_seconds': 4,
          },
        );

        // Wait 500ms to ensure the lock is acquired before we attempt our insert.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final evidence = {
          'clause_ref': 'rule-fail-closed-001',
          'rule_id': 'rule-fail-closed-001',
          'rule_version': 1,
          'fine_cents': fineAmount,
        };

        // This insert should hit the 2s lock_timeout, catch it, and fail-closed.
        final insertFuture = seed
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

        final results = await Future.wait<dynamic>([
          lockFuture as Future<dynamic>,
          insertFuture as Future<dynamic>,
        ]);
        final ledgerId = (results[1] as Map<String, dynamic>)['id'] as String;

        // 1. Verify ledger row was inserted and properly mutated
        final row = await seed
            .from('sla_audit_ledger_v2')
            .select('payload')
            .eq('id', ledgerId)
            .single();
        final payload = row['payload'] as Map<String, dynamic>;

        final verdictEvidence =
            payload['verdict_evidence'] as Map<String, dynamic>;
        expect(
          verdictEvidence['fine_cents'],
          0,
          reason: 'Fine should be forced to 0 on lock timeout',
        );

        expect(
          payload['original_fine_cents'],
          fineAmount,
          reason: 'Original fine must be preserved',
        );
        expect(payload['cap_truncated'], true);
        expect(payload['cap_check_deferred'], true);

        final capMonthStr = payload['cap_month_utc'] as String?;
        expect(capMonthStr, isNotNull, reason: 'cap_month_utc must be present');
        final normalizedStr = capMonthStr!.contains('T')
            ? capMonthStr
            : '${capMonthStr}T00:00:00Z';
        final capMonth = DateTime.parse(normalizedStr).toUtc();
        final currentMonth = DateTime.utc(
          DateTime.now().toUtc().year,
          DateTime.now().toUtc().month,
          1,
        );
        expect(
          capMonth,
          currentMonth,
          reason: 'cap_month_utc should match the current month',
        );

        // 2. Verify accrual was untouched (no row created, or at least 0 cents)
        final accrual = await seed
            .from('contract_penalty_monthly_accrual')
            .select('accrued_cents')
            .eq('contract_id', contractId)
            .maybeSingle();
        if (accrual != null) {
          expect(
            accrual['accrued_cents'],
            0,
            reason: 'Accrual should be exactly 0',
          );
        }

        // 3. Verify FINANCIAL_CAP_DEFERRED in system_audit_log
        final auditLogs = await seed
            .from('system_audit_log')
            .select()
            .eq('event_type', 'FINANCIAL_CAP_DEFERRED')
            .filter('payload->>deferred_ledger_entry_id', 'eq', ledgerId);
        expect(
          auditLogs.length,
          1,
          reason: 'Exactly one FINANCIAL_CAP_DEFERRED log expected',
        );

        // 4. Run reconcile_financial_guard. It scans every capped contract in the
        // org, so the global correction count is not a reliable per-test signal
        // (sibling contracts in a shared DB may legitimately drift). Assert instead
        // that reconcile logs NO drift for OUR fail-closed contract — the fine sealed
        // as 0 with 0 accrual is already self-consistent, nothing to correct.
        await seed.rpc<int>(
          'reconcile_financial_guard',
          params: {'p_organization_id': _orgId},
        );
        final driftLogs = await seed
            .from('system_audit_log')
            .select()
            .eq('event_type', 'FINANCIAL_GUARD_DRIFT')
            .filter('payload->>contract_id', 'eq', contractId);

        expect(
          driftLogs.length,
          0,
          reason: 'Reconcile should not flag our fail-closed row as drift',
        );
      });
    },
  );
}
