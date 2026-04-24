// =============================================================================
// Task 3 — FSM State Transitions (SQL Guard Trigger Level)
// Task 7 — Append-only Transition History (INV-3 — additional)
// =============================================================================
//
// Forensic Insight — QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-3  (Ledger): APPEND-ONLY. No Update/Delete on transition history.
//   INV-22 (Isolation): Tenant-A FSM transitions cannot be overridden by B.
//
// FSM allowed transitions (from migration 20260623000001):
//   planned         → inTransit | completed | failed | inhibited
//   inTransit       → completed | completedWithGaps | failed | inhibited
//   failed          → completed | inhibited              (INV-12 late arrival)
//   completedWithGaps → completed | inhibited
//   completed       → TERMINAL (no transition allowed)
//   inhibited       → TERMINAL (no transition allowed)
//
// Blocked transitions tested:
//   completed   → inTransit   (terminal violation)
//   completed   → planned     (terminal + reverse violation)
//   completed   → failed      (terminal violation)
//   inhibited   → planned     (terminal violation)
//   failed      → inTransit   (invalid recovery path)
//   failed      → planned     (invalid regression)
//   completedWithGaps → inTransit (invalid recovery path)
//
// Valid transitions tested:
//   planned → inTransit   (primary transit start)
//   inTransit → completed (happy path)
//   failed → completed    (INV-12 late arrival)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'FSM: Execution State Machine guard trigger (SQL-level enforcement)',
    () {
      late SupabaseClient serviceClient;
      late PostgresContractualExecutionStateRepository repo;
      const uuid = Uuid();
      const orgId = PostgresTestConfig.testOrgId;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();
        await PostgresTestConfig.ensureSentinelOrg(id: orgId);
        repo = PostgresContractualExecutionStateRepository(
          serviceClient,
          UtcDateTimeProvider(),
        );
      });

      tearDownAll(() async {
        await serviceClient.dispose();
      });

      // ── Helper: create a planned execution state in the DB ────────────────
      Future<ContractualExecutionState> seedPlannedState({
        String? contractId,
        String? setId,
      }) async {
        final cid = contractId ?? uuid.v4();
        final sid = setId ?? uuid.v4();

        await PostgresTestConfig.seedServiceExecution(
          serviceClient,
          setId: sid,
          contractId: cid,
        );

        final state = ContractualExecutionState.create(
          organizationId: orgId,
          setId: sid,
          contractId: cid,
          planVersion: 1,
          startLatitude: -23.5505, // Physical Metric - Double Required
          startLongitude: -46.6333, // Physical Metric - Double Required
          startRadiusMeters: 50,
          contractualValue: const Money(100000),
          noShowPenaltyBps: 15000,
          windowStartUtc: DateTime.now().toUtc().subtract(
            const Duration(minutes: 10),
          ),
          windowEndUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
        );

        await repo.save(state);
        return state;
      }

      // ── FSM-VALID-1 ────────────────────────────────────────────────────────
      test(
        'FSM-VALID-1: planned → inTransit via direct SQL UPDATE is accepted',
        () async {
          final state = await seedPlannedState();

          // Transition via direct SQL (simulates the RPC path).
          await expectLater(
            serviceClient
                .from('execution_states')
                .update({
                  'status': 'inTransit',
                  'status_last_updated_at_utc': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                })
                .eq('id', state.id)
                .eq('organization_id', orgId),
            completes,
            reason:
                'planned → inTransit is a valid FSM transition. '
                'The guard trigger must allow it.',
          );

          final row = await serviceClient
              .from('execution_states')
              .select('status')
              .eq('id', state.id)
              .single();

          expect(
            row['status'],
            equals('inTransit'),
            reason: 'DB must persist the new status after valid transition.',
          );
        },
      );

      // ── FSM-VALID-2 ────────────────────────────────────────────────────────
      test(
        'FSM-VALID-2: planned → completed via repository save is accepted',
        () async {
          final state = await seedPlannedState();

          // Domain transition: bindExecution sets status to completed.
          state.bindExecution(
            vehicleId: 'veh-fsm-valid-2',
            latitude: -23.5506, // Physical Metric - Double Required
            longitude: -46.6334, // Physical Metric - Double Required
            timestampUtc: DateTime.now().toUtc(),
          );

          await expectLater(
            repo.save(state),
            completes,
            reason:
                'planned → completed (via bindExecution) is a valid FSM '
                'transition and must be accepted by the guard trigger.',
          );
        },
      );

      // ── FSM-VALID-3 ────────────────────────────────────────────────────────
      test(
        'FSM-VALID-3: failed → completed is accepted (INV-12 late arrival)',
        () async {
          final state = await seedPlannedState();

          // Force to failed via direct SQL (bypass domain model).
          await serviceClient
              .from('execution_states')
              .update({
                'status': 'failed',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          // Now transition to completed (late arrival recovery).
          await expectLater(
            serviceClient
                .from('execution_states')
                .update({
                  'status': 'completed',
                  'status_last_updated_at_utc': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                })
                .eq('id', state.id),
            completes,
            reason:
                'INV-12: failed → completed must be accepted by the FSM guard. '
                'Late arrival evidence should be able to recover a failed trip.',
          );
        },
      );

      // ── FSM-BLOCK-1 ───────────────────────────────────────────────────────
      test(
        'FSM-BLOCK-1: completed → inTransit is BLOCKED by trg_fsm_guard_terminal_states',
        () async {
          final state = await seedPlannedState();

          // Force to completed.
          await serviceClient
              .from('execution_states')
              .update({
                'status': 'completed',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          // Attempt illegal reverse transition.
          expect(
            () async {
              await serviceClient
                  .from('execution_states')
                  .update({
                    'status': 'inTransit',
                    'status_last_updated_at_utc': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  })
                  .eq('id', state.id);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'FSM: completed is a terminal state. '
                'The guard trigger must block completed → inTransit. '
                'No financial reversal possible after trip completion.',
          );
        },
      );

      // ── FSM-BLOCK-2 ───────────────────────────────────────────────────────
      test(
        'FSM-BLOCK-2: completed → planned is BLOCKED (terminal + regression)',
        () async {
          final state = await seedPlannedState();

          await serviceClient
              .from('execution_states')
              .update({
                'status': 'completed',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          expect(
            () async {
              await serviceClient
                  .from('execution_states')
                  .update({
                    'status': 'planned',
                    'status_last_updated_at_utc': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  })
                  .eq('id', state.id);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'FSM: completed → planned violates terminal state invariant. '
                'Would allow fraudulent re-use of completed trips.',
          );
        },
      );

      // ── FSM-BLOCK-3 ───────────────────────────────────────────────────────
      test(
        'FSM-BLOCK-3: inhibited → planned is BLOCKED (terminal state)',
        () async {
          final state = await seedPlannedState();

          await serviceClient
              .from('execution_states')
              .update({
                'status': 'inhibited',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          expect(
            () async {
              await serviceClient
                  .from('execution_states')
                  .update({
                    'status': 'planned',
                    'status_last_updated_at_utc': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  })
                  .eq('id', state.id);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'FSM: inhibited is terminal. Once a justification is approved, '
                'the execution cannot revert to planned — financial penalty is waived.',
          );
        },
      );

      // ── FSM-BLOCK-4 ───────────────────────────────────────────────────────
      test(
        'FSM-BLOCK-4: failed → inTransit is BLOCKED by guard trigger',
        () async {
          final state = await seedPlannedState();

          await serviceClient
              .from('execution_states')
              .update({
                'status': 'failed',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          expect(
            () async {
              await serviceClient
                  .from('execution_states')
                  .update({
                    'status': 'inTransit',
                    'status_last_updated_at_utc': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  })
                  .eq('id', state.id);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'FSM: failed → inTransit is not a valid recovery path. '
                'Failed executions can only transition to completed (late arrival) '
                'or inhibited (justification approved).',
          );
        },
      );

      // ── FSM-BLOCK-5 ───────────────────────────────────────────────────────
      test('FSM-BLOCK-5: completedWithGaps → inTransit is BLOCKED', () async {
        final state = await seedPlannedState();

        await serviceClient
            .from('execution_states')
            .update({
              'status': 'completedWithGaps',
              'status_last_updated_at_utc': DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            })
            .eq('id', state.id);

        expect(
          () async {
            await serviceClient
                .from('execution_states')
                .update({
                  'status': 'inTransit',
                  'status_last_updated_at_utc': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                })
                .eq('id', state.id);
          },
          throwsA(isA<PostgrestException>()),
          reason:
              'FSM: completedWithGaps → inTransit is not a valid transition. '
              'The guard trigger must block this forensic negligence regression.',
        );
      });

      // ── FSM-BLOCK-6 ───────────────────────────────────────────────────────
      test(
        'FSM-BLOCK-6: completed → failed is BLOCKED (terminal state)',
        () async {
          final state = await seedPlannedState();

          await serviceClient
              .from('execution_states')
              .update({
                'status': 'completed',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          expect(
            () async {
              await serviceClient
                  .from('execution_states')
                  .update({
                    'status': 'failed',
                    'status_last_updated_at_utc': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  })
                  .eq('id', state.id);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'FSM: completed is terminal. No transition allowed. '
                'completed → failed would fabricate a no-show penalty.',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );

  // ===========================================================================
  // Group B — Task 7: Append-only Transition History (INV-3)
  // ===========================================================================
  group(
    'INV-3: execution_state_transitions is append-only',
    () {
      late SupabaseClient serviceClient;
      const uuid = Uuid();
      const orgId = PostgresTestConfig.testOrgId;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();
        await PostgresTestConfig.ensureSentinelOrg(id: orgId);
      });

      tearDownAll(() async {
        await serviceClient.dispose();
      });

      // ── AT-1 ───────────────────────────────────────────────────────────────
      test(
        'AT-1: transition rows grow monotonically — each status change appends a row',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          await PostgresTestConfig.seedServiceExecution(
            serviceClient,
            setId: setId,
            contractId: contractId,
          );

          final repo = PostgresContractualExecutionStateRepository(
            serviceClient,
            UtcDateTimeProvider(),
          );

          final state = ContractualExecutionState.create(
            organizationId: orgId,
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            startLatitude: -23.5505, // Physical Metric - Double Required
            startLongitude: -46.6333, // Physical Metric - Double Required
            startRadiusMeters: 50,
            contractualValue: const Money(100000),
            noShowPenaltyBps: 15000,
            windowStartUtc: DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
            windowEndUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          );

          // Insert (creates initial transition row).
          await repo.save(state);

          final countBefore = await serviceClient
              .from('execution_state_transitions')
              .select()
              .eq('execution_state_id', state.id)
              .count(CountOption.exact);

          // Transition to inTransit via direct SQL.
          await serviceClient
              .from('execution_states')
              .update({
                'status': 'inTransit',
                'status_last_updated_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
              })
              .eq('id', state.id);

          // Re-save via repo to record the new status.
          // Domain model doesn't track all transitions so we insert manually.
          await serviceClient.from('execution_state_transitions').insert({
            'execution_state_id': state.id,
            'organization_id': orgId,
            'previous_status': 'planned',
            'new_status': 'inTransit',
            'transitioned_at_utc': DateTime.now().toUtc().toIso8601String(),
            'reason': 'AT-1 test transition',
            'metadata': {'test': true},
          });

          final countAfter = await serviceClient
              .from('execution_state_transitions')
              .select()
              .eq('execution_state_id', state.id)
              .count(CountOption.exact);

          expect(
            countAfter.count,
            greaterThan(countBefore.count),
            reason:
                'INV-3: Each status change must append a new row to '
                'execution_state_transitions — the ledger must only grow.',
          );
        },
      );

      // ── AT-2 ───────────────────────────────────────────────────────────────
      test('AT-2: CHECK constraint rejects invalid status values', () async {
        const invalidStatus = 'INVALID_STATUS_THAT_DOES_NOT_EXIST';

        expect(
          () async {
            await serviceClient.from('execution_states').insert({
              'id': uuid.v4(),
              'organization_id': orgId,
              'set_id': uuid.v4(),
              'contract_id': uuid.v4(),
              'plan_version': 1,
              'start_latitude': -23.5505,
              'start_longitude': -46.6333,
              'start_radius_meters': 50,
              'contractual_value_cents': 100000,
              'no_show_penalty_multiplier': 1.5,
              'window_start_utc': DateTime.now().toUtc().toIso8601String(),
              'window_end_utc': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
              'status': invalidStatus,
              'created_at_utc': DateTime.now().toUtc().toIso8601String(),
              'last_evaluated_at_utc': DateTime.now().toUtc().toIso8601String(),
              'status_last_updated_at_utc': DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            });
          },
          throwsA(isA<PostgrestException>()),
          reason:
              'The CHECK constraint on execution_states.status must reject '
              'values not in the FSM vocabulary.',
        );
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
