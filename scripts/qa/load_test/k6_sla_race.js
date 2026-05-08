// =============================================================================
// Phase 10 — Chaos Test: SLA Racing & Determinism (INV-15)
// =============================================================================
//
// SCENARIO A — race_complete:
//   Two concurrent requests fire complete_execution on the SAME set_id.
//   One wins (returns true, writes 1 transition row). The other loses
//   (returns false or idempotent true). The DB must never write 2 transition
//   rows for the same set_id → completed event.
//   PASS: COUNT(execution_state_transitions WHERE new_status='completed') = 1 per set_id.
//
// SCENARIO B — reopen_attempt:
//   After completion, a direct REST PATCH attempts to reopen the execution
//   (status → 'inTransit'). The FSM trigger must raise restrict_violation.
//   PASS: Response status 409 or 500 with 'restrict_violation' in body.
//
// SCENARIO C — idempotent_complete:
//   Call complete_execution N times on an already-completed execution.
//   PASS: All calls return true, still only 1 transition row.
//
// DESIGN NOTE:
//   Uses http.batch() within a single iteration to race two concurrent requests.
//   This exercises the same DB row-lock contention as two Edge Function instances
//   processing simultaneous webhooks (Ping A geofence-enter, Ping B deviation).
//
// RUN:
//   export SUPABASE_URL=http://localhost:54321
//   export SUPABASE_ANON_KEY=<anon_key>
//   export SERVICE_ROLE_KEY=<service_role_key>
//   export ORG_ID=00000000-0000-0000-0000-000000000001
//   export CONTRACT_ID=00000000-0000-0000-0000-ca0000000001
//   k6 run scripts/load_test/k6_sla_race.js
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const SUPABASE_URL     = __ENV.SUPABASE_URL     || 'http://localhost:54321';
const ANON_KEY         = __ENV.SUPABASE_ANON_KEY || '';
const SERVICE_ROLE_KEY = __ENV.SERVICE_ROLE_KEY  || '';
const ORG_ID           = __ENV.ORG_ID            || '00000000-0000-0000-0000-000000000001';
const CONTRACT_ID      = __ENV.CONTRACT_ID       || '00000000-0000-0000-0000-ca0000000001';
const PLAN_VERSION     = parseInt(__ENV.PLAN_VERSION || '1', 10);

const REST_BASE = `${SUPABASE_URL}/rest/v1`;
const RPC_BASE  = `${SUPABASE_URL}/rest/v1/rpc`;

const HEADERS_SERVICE = {
  'Content-Type':  'application/json',
  'apikey':        SERVICE_ROLE_KEY,
  'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  'Prefer':        'return=representation',
};

const HEADERS_ANON = {
  'Content-Type':  'application/json',
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ANON_KEY}`,
  'Prefer':        'return=minimal',
};

// ── Custom metrics ─────────────────────────────────────────────────────────────
const raceWinnerLatency     = new Trend('sla_race_winner_ms', true);
const duplicateCompletions  = new Counter('sla_duplicate_completions');
const fsm_violations_caught = new Counter('sla_fsm_violations_caught');
const reopenBlocked         = new Rate('sla_reopen_blocked_rate');

// ── Options ────────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // A. Race: 30 pairs of concurrent complete_execution calls
    race_complete: {
      executor:     'per-vu-iterations',
      vus:          30,
      iterations:   1,
      maxDuration:  '2m',
      exec:         'raceCompleteScenario',
      gracefulStop: '15s',
    },

    // B. Reopen: 20 VUs try to reopen completed executions
    reopen_attempt: {
      executor:     'per-vu-iterations',
      vus:          20,
      iterations:   1,
      maxDuration:  '2m',
      exec:         'reopenAttemptScenario',
      startTime:    '2m30s',
      gracefulStop: '15s',
    },

    // C. Idempotent: 10 VUs call complete on already-completed, 5 times each
    idempotent_complete: {
      executor:     'per-vu-iterations',
      vus:          10,
      iterations:   5,
      maxDuration:  '2m',
      exec:         'idempotentCompleteScenario',
      startTime:    '5m',
      gracefulStop: '15s',
    },
  },

  thresholds: {
    // Zero duplicate completion transition rows (hard fail — INV-15)
    'sla_duplicate_completions':   [{ threshold: 'count==0', abortOnFail: true }],
    // All reopen attempts must be blocked (100%)
    'sla_reopen_blocked_rate':     [{ threshold: 'rate==1', abortOnFail: true }],
    // Race winner latency p95 < 500ms under concurrent load
    'sla_race_winner_ms':          [{ threshold: 'p(95)<500', abortOnFail: false }],
    // FSM violations caught (informational — higher is better for Scenario B)
    'http_req_failed':             [{ threshold: 'rate<0.05', abortOnFail: false }],
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function createInTransitExecution(setId) {
  // 1. Create plan_declaration (required FK)
  const planId = makeUUID();
  const planRes = http.post(`${REST_BASE}/plan_declarations`, JSON.stringify({
    id:                  planId,
    contract_id:         CONTRACT_ID,
    declared_at_utc:     new Date().toISOString(),
    declared_by_user_id: 'k6_sla_race_test',
    plan_version:        PLAN_VERSION + Math.floor(Math.random() * 10000),
    original_file_hash:  `k6-hash-${makeUUID()}`,
  }), { headers: HEADERS_SERVICE });

  if (planRes.status !== 201) return null;

  // 2. Create contractual_service_execution (required FK for execution_states)
  const cseRes = http.post(`${REST_BASE}/contractual_service_executions`, JSON.stringify({
    set_id:                    setId,
    plan_declaration_id:       planId,
    scheduled_start_time_utc:  new Date(Date.now() - 3600_000).toISOString(),
    scheduled_end_time_utc:    new Date(Date.now() + 3600_000).toISOString(),
    start_latitude:            -23.5505,
    start_longitude:           -46.6333,
    start_radius_meters:       200,
    end_latitude:              -23.5505,
    end_longitude:             -46.6333,
    end_radius_meters:         200,
    contractual_value_cents:   100_00,
    no_show_penalty_multiplier: 1.5,
  }), { headers: HEADERS_SERVICE });

  if (cseRes.status !== 201) return null;

  // 3. Create execution_state in inTransit
  const stateRes = http.post(`${REST_BASE}/execution_states`, JSON.stringify({
    id:                         makeUUID(),
    set_id:                     setId,
    organization_id:            ORG_ID,
    contract_id:                CONTRACT_ID,
    plan_version:               PLAN_VERSION,
    start_latitude:             -23.5505,
    start_longitude:            -46.6333,
    start_radius_meters:        200,
    contractual_value_cents:    100_00,
    no_show_penalty_multiplier: 1.5,
    window_start_utc:           new Date(Date.now() - 3600_000).toISOString(),
    window_end_utc:             new Date(Date.now() + 3600_000).toISOString(),
    status:                     'inTransit',
    created_at_utc:             new Date().toISOString(),
    last_evaluated_at_utc:      new Date().toISOString(),
    status_last_updated_at_utc: new Date().toISOString(),
  }), { headers: HEADERS_SERVICE });

  return stateRes.status === 201 ? setId : null;
}

function countTransitions(setId) {
  const res = http.get(
    `${REST_BASE}/execution_state_transitions` +
    `?new_status=eq.completed` +
    `&metadata->>set_id=eq.${setId}`,
    { headers: { ...HEADERS_SERVICE, 'Prefer': 'count=exact' } },
  );

  try {
    return JSON.parse(res.body || '[]').length;
  } catch {
    return -1;
  }
}

function callCompleteExecution(setId, reason) {
  return {
    method:  'POST',
    url:     `${RPC_BASE}/complete_execution`,
    headers: HEADERS_SERVICE,
    body:    JSON.stringify({ p_org_id: ORG_ID, p_set_id: setId, p_reason: reason }),
  };
}

// ── Scenario A: Race Complete ──────────────────────────────────────────────────
// Two simultaneous complete_execution calls on the same set_id.
// Verifies: exactly 1 transition row written regardless of winner.
export function raceCompleteScenario() {
  const setId = `race-${__VU}-${makeUUID().slice(0, 8)}`;

  const created = createInTransitExecution(setId);
  if (!created) {
    console.error(`[race] VU ${__VU}: failed to create inTransit execution`);
    return;
  }

  // Fire two concurrent complete requests — simulates Ping A (geofence) + Ping B (deviation)
  const start = Date.now();
  const [resA, resB] = http.batch([
    callCompleteExecution(setId, 'PING_A_GEOFENCE_ENTER'),
    callCompleteExecution(setId, 'PING_B_DEVIATION_ALERT'),
  ]);
  const elapsed = Date.now() - start;
  raceWinnerLatency.add(elapsed);

  group('race_complete', () => {
    const aBody = resA.body ? JSON.parse(resA.body) : null;
    const bBody = resB.body ? JSON.parse(resB.body) : null;

    check(resA, { 'raceA: status 200': r => r.status === 200 });
    check(resB, { 'raceB: status 200': r => r.status === 200 });

    // Both may return true (idempotent) — that is acceptable.
    // What must NOT happen: 2 transition rows with new_status='completed'.
    sleep(0.1); // Brief pause to let DB commit settle

    const transCount = countTransitions(setId);
    if (transCount > 1) {
      duplicateCompletions.add(transCount - 1);
      console.error(
        `DETERMINISM BREACH: set_id=${setId} has ${transCount} completed transitions!` +
        ` PingA: ${resA.body}, PingB: ${resB.body}`
      );
    }

    check(null, {
      'race: only 1 completion transition': () => transCount === 1,
    });
  });
}

// ── Scenario B: Reopen Attempt ─────────────────────────────────────────────────
// After completion, try to force-update status back to 'inTransit' via REST PATCH.
// FSM trigger must block with restrict_violation.
export function reopenAttemptScenario() {
  const setId = `reopen-${__VU}-${makeUUID().slice(0, 8)}`;

  const created = createInTransitExecution(setId);
  if (!created) return;

  // Complete the execution first
  http.post(`${RPC_BASE}/complete_execution`, JSON.stringify({
    p_org_id: ORG_ID,
    p_set_id: setId,
    p_reason: 'TEST_COMPLETE',
  }), { headers: HEADERS_SERVICE });

  // Now attempt to reopen (must be blocked by FSM trigger)
  const reopenRes = http.patch(
    `${REST_BASE}/execution_states?set_id=eq.${setId}&organization_id=eq.${ORG_ID}`,
    JSON.stringify({ status: 'inTransit' }),
    { headers: HEADERS_SERVICE },
  );

  const blocked = reopenRes.status >= 400;
  reopenBlocked.add(blocked ? 1 : 0);

  if (!blocked) {
    console.error(
      `FSM BREACH: Reopen of completed execution ${setId} SUCCEEDED with status ${reopenRes.status}`
    );
  }

  if (blocked) fsm_violations_caught.add(1);

  check(reopenRes, {
    'reopen: blocked by FSM trigger':        r => r.status >= 400,
    'reopen: restrict_violation or similar': r =>
      (r.body && (r.body.includes('restrict_violation') || r.body.includes('FSM'))) ||
      r.status === 409 || r.status === 500 || r.status === 400,
  });
}

// ── Scenario C: Idempotent Complete ───────────────────────────────────────────
// Call complete_execution 5× on the same already-completed execution.
// All must return true (first-wins idempotency). Still only 1 transition row.
export function idempotentCompleteScenario() {
  // Use a shared completed set_id derived from VU (created once per VU, reused 5×)
  const setId = `idempotent-${__VU}`;

  if (__ITER === 0) {
    createInTransitExecution(setId);
    // Complete once
    http.post(`${RPC_BASE}/complete_execution`, JSON.stringify({
      p_org_id: ORG_ID,
      p_set_id: setId,
      p_reason: 'INITIAL_COMPLETE',
    }), { headers: HEADERS_SERVICE });
  }

  // Subsequent calls must be idempotent
  const res = http.post(`${RPC_BASE}/complete_execution`, JSON.stringify({
    p_org_id: ORG_ID,
    p_set_id: setId,
    p_reason: `IDEMPOTENT_CALL_${__ITER}`,
  }), { headers: HEADERS_SERVICE });

  check(res, {
    'idempotent: status 200':      r => r.status === 200,
    'idempotent: returns true':    r => r.body === 'true',
  });

  // On last iteration, verify still only 1 transition row
  if (__ITER === 4) {
    const count = countTransitions(setId);
    check(null, {
      'idempotent: exactly 1 transition row after 5 calls': () => count === 1,
    });
  }

  sleep(0.2);
}

// ── Summary ────────────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const duplicates    = data.metrics['sla_duplicate_completions']?.values?.count   ?? 0;
  const reopenRate    = data.metrics['sla_reopen_blocked_rate']?.values?.rate      ?? 0;
  const fsmCaught     = data.metrics['sla_fsm_violations_caught']?.values?.count   ?? 0;
  const raceP95       = data.metrics['sla_race_winner_ms']?.values?.['p(95)']      ?? 'N/A';

  const determinismPass = duplicates === 0 ? '✅ PASS (ZERO DUPLICATES)' : `❌ FAIL — ${duplicates} DUPLICATE(S)`;
  const reopenPass      = reopenRate  === 1 ? '✅ PASS (100% BLOCKED)'   : `❌ FAIL — rate=${reopenRate.toFixed(3)}`;

  const report = [
    '=================================================================',
    ' VeraProb Phase 10 — SLA Racing & Determinism Test (INV-15)',
    '=================================================================',
    '',
    ' SCENARIO A: Concurrent complete_execution (Race)',
    ` Duplicate completion transitions: ${duplicates}   ${determinismPass}`,
    ` Race latency p95: ${typeof raceP95 === 'number' ? raceP95.toFixed(1) : raceP95} ms`,
    '',
    ' SCENARIO B: Reopen Attempt After Completion',
    ` Reopen blocked rate: ${(reopenRate * 100).toFixed(1)}%   ${reopenPass}`,
    ` FSM violation exceptions caught: ${fsmCaught}`,
    '',
    ' SCENARIO C: Idempotent complete_execution (5× calls)',
    '   Check: all returned true, still 1 transition row. See checks above.',
    '',
    ' VERIFICATION SQL (run in Supabase SQL Editor):',
    '   -- Check for duplicate completion transitions (must be 0):',
    "   SELECT set_id, COUNT(*) AS completions",
    "   FROM execution_state_transitions est",
    "   JOIN execution_states es ON es.id = est.execution_state_id",
    "   WHERE est.new_status = 'completed'",
    "     AND es.set_id LIKE 'race-%'",
    "   GROUP BY set_id HAVING COUNT(*) > 1;",
    '   -- Expected: 0 rows',
    '',
    "   -- Verify FSM blocks reopen:",
    "   SELECT status FROM execution_states WHERE set_id LIKE 'reopen-%' LIMIT 5;",
    '   -- Expected: all rows show status = completed',
    '=================================================================',
  ].join('\n');

  console.log(report);
  return {
    'stdout': report + '\n',
    'docs/governance/k6_sla_race_results.json': JSON.stringify(data, null, 2),
  };
}
