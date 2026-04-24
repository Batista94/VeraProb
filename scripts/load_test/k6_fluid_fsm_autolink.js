// =============================================================================
// Phase 10.3 — TDD Test: Fluid FSM Shadow Auto-Link (INV-11, INV-15)
// =============================================================================
//
// ⚠️  TDD GATE (INV-11): This test MUST FAIL before migration
//     20260702000002_shadow_autolink_trigger.sql is applied.
//     After applying the migration, all checks must PASS.
//     Do not bypass this gate.
//
// SCENARIO:
//   1. Create a telegram_evidence_uploads row (simulating orphan evidence
//      that arrived when no trip was active → became an UNLINKED_SHADOW).
//   2. Create a new execution_states row whose window_start/end retroactively
//      covers the evidence message_ts.
//   3. The auto_link_shadows_to_execution trigger should automatically
//      transition the shadow from UNLINKED_SHADOW → RECONCILED.
//   4. Verify: shadow.status = 'RECONCILED', shadow.reconciled_execution_id = set_id.
//   5. Verify: NO hash collision — the evidence forensic_hash is unchanged.
//   6. Verify: shadow_execution_transitions has exactly 1 transition row for this shadow.
//
// PASS CRITERIA:
//   - autolink_success_rate == 1.0 (100% of shadows auto-linked)
//   - hash_collision_count == 0    (forensic hash unchanged)
//   - duplicate_shadow_count == 0  (no duplicate reconciliation rows)
//
// RUN:
//   # Before migration (should FAIL — establishes baseline):
//   k6 run scripts/load_test/k6_fluid_fsm_autolink.js
//
//   # Apply migration:
//   supabase db push
//
//   # After migration (must PASS):
//   k6 run scripts/load_test/k6_fluid_fsm_autolink.js
//
// ENV:
//   SUPABASE_URL=http://localhost:54321
//   SERVICE_ROLE_KEY=<service_role_key>
//   ORG_ID=00000000-0000-0000-0000-000000000001
//   OPERATOR_ID=<operator_uuid>
//   CONTRACT_ID=<contract_id>
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const SUPABASE_URL     = __ENV.SUPABASE_URL      || 'http://localhost:54321';
const SERVICE_ROLE_KEY = __ENV.SERVICE_ROLE_KEY  || '';
const ORG_ID           = __ENV.ORG_ID            || '00000000-0000-0000-0000-000000000001';
// OPERATOR_ID is used as the driver_id FK in telegram_evidence_uploads AND
// as p_operator_id in create_shadow_execution. Must exist in public.drivers
// for the test org. Seed SQL or: INSERT INTO drivers(id, organization_id, ...).
const OPERATOR_ID      = __ENV.OPERATOR_ID       || '00000000-0000-0000-0000-000000000099';
const CONTRACT_ID      = __ENV.CONTRACT_ID       || '00000000-0000-0000-0000-ca0000000001';
const PLAN_VERSION     = parseInt(__ENV.PLAN_VERSION || '1', 10);

const REST_BASE = `${SUPABASE_URL}/rest/v1`;
const RPC_BASE  = `${SUPABASE_URL}/rest/v1/rpc`;

const HEADERS = {
  'Content-Type':  'application/json',
  'apikey':        SERVICE_ROLE_KEY,
  'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  'Prefer':        'return=representation',
};

// ── Custom metrics ─────────────────────────────────────────────────────────────
const autolinkRate       = new Rate('fluid_fsm_autolink_success_rate');
const hashCollisions     = new Counter('fluid_fsm_hash_collision_count');
const duplicateShadows   = new Counter('fluid_fsm_duplicate_shadow_count');
const autolinkLatency    = new Trend('fluid_fsm_autolink_latency_ms', true);

// ── Options ────────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Main scenario: 30 concurrent shadow → retroactive-trip pairs
    autolink_test: {
      executor:     'per-vu-iterations',
      vus:          30,
      iterations:   1,
      maxDuration:  '5m',
      exec:         'autolinkScenario',
      gracefulStop: '30s',
    },

    // Concurrent auto-link: multiple retroactive trips covering overlapping windows
    concurrent_autolink: {
      executor:     'per-vu-iterations',
      vus:          10,
      iterations:   1,
      maxDuration:  '3m',
      exec:         'concurrentAutolinkScenario',
      startTime:    '6m',
      gracefulStop: '15s',
    },
  },

  thresholds: {
    // 100% of shadows must be auto-linked after retroactive trip creation (INV-11)
    'fluid_fsm_autolink_success_rate': [{ threshold: 'rate==1', abortOnFail: true }],
    // Zero hash collisions (forensic hash immutability — INV-9)
    'fluid_fsm_hash_collision_count':  [{ threshold: 'count==0', abortOnFail: true }],
    // Zero duplicate reconciliation rows (INV-15)
    'fluid_fsm_duplicate_shadow_count': [{ threshold: 'count==0', abortOnFail: true }],
    // Auto-link trigger latency p95 < 1s (includes INSERT + trigger + SELECT)
    'fluid_fsm_autolink_latency_ms':   [{ threshold: 'p(95)<1000', abortOnFail: false }],
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function sha256Hex(str) {
  // k6 does not expose crypto.subtle. Use a deterministic fake hash for test
  // isolation — the invariant is that the hash is UNCHANGED after auto-link.
  // In real ingestion, the hash is computed server-side (SHA-256 of file bytes).
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h).toString(16).padStart(64, '0');
}

function createEvidenceRow(chatId, messageId, messageTs) {
  // Insert directly into telegram_evidence_uploads as service role.
  // Simulates evidence arriving with no active execution (orphan).
  // Schema (after all migrations): organization_id, driver_id, chat_id,
  //   telegram_message_id, file_name, forensic_hash (64 hex), storage_path,
  //   source, linked_set_id, telegram_message_date, requires_manual_link,
  //   mime_type, clock_drift_seconds.
  // driver_id FK requires a real driver row in public.drivers for test org.
  const forensicHash = sha256Hex(`evidence-${chatId}-${messageId}`).slice(0, 64);
  const res = http.post(`${REST_BASE}/telegram_evidence_uploads`, JSON.stringify({
    organization_id:       ORG_ID,
    driver_id:             OPERATOR_ID, // OPERATOR_ID env var reused as DRIVER_ID for seed consistency
    chat_id:               chatId,
    telegram_message_id:   messageId,
    file_name:             makeUUID() + '.jpg',
    forensic_hash:         forensicHash,
    storage_path:          ORG_ID + '/telegram/' + chatId + '/' + makeUUID() + '.jpg',
    source:                'telegram',
    linked_set_id:         null,
    telegram_message_date: new Date(messageTs * 1000).toISOString(),
    requires_manual_link:  true,
    mime_type:             'image/jpeg',
    clock_drift_seconds:   0,
  }), { headers: HEADERS });

  if (res.status !== 201) {
    console.error(`Failed to create evidence: ${res.status} ${res.body}`);
    return null;
  }

  let row;
  try { row = JSON.parse(res.body)[0]; } catch { return null; }
  return { id: row?.id, forensicHash };
}

function createShadowExecution(evidenceId, chatId, messageTs) {
  const res = http.post(`${RPC_BASE}/create_shadow_execution`, JSON.stringify({
    p_org_id:              ORG_ID,
    p_operator_id:         OPERATOR_ID,
    p_chat_id:             chatId,
    p_evidence_id:         evidenceId,
    p_telegram_message_id: chatId * 1000 + Math.floor(messageTs % 1000),
    p_message_ts:          messageTs,
  }), { headers: HEADERS });

  if (res.status !== 200) {
    console.error(`Failed to create shadow: ${res.status} ${res.body}`);
    return null;
  }

  try { return JSON.parse(res.body); } catch { return null; }
}

function createRetroactiveExecution(setId, windowStartTs, windowEndTs) {
  // First create plan_declaration (required FK)
  const planId  = makeUUID();
  const planRes = http.post(`${REST_BASE}/plan_declarations`, JSON.stringify({
    id:                  planId,
    contract_id:         CONTRACT_ID,
    declared_at_utc:     new Date().toISOString(),
    declared_by_user_id: 'k6_fluid_fsm_test',
    plan_version:        Math.floor(Math.random() * 100000),
    original_file_hash:  sha256Hex(`plan-${setId}`),
  }), { headers: HEADERS });

  if (planRes.status !== 201) return false;

  // Create contractual_service_execution
  const cseRes = http.post(`${REST_BASE}/contractual_service_executions`, JSON.stringify({
    set_id:                    setId,
    plan_declaration_id:       planId,
    scheduled_start_time_utc:  new Date(windowStartTs * 1000).toISOString(),
    scheduled_end_time_utc:    new Date(windowEndTs   * 1000).toISOString(),
    start_latitude:            -23.5505,
    start_longitude:           -46.6333,
    start_radius_meters:       200,
    end_latitude:              -23.5505,
    end_longitude:             -46.6333,
    end_radius_meters:         200,
    contractual_value_cents:   100_00,
    no_show_penalty_multiplier: 1.0,
  }), { headers: HEADERS });

  if (cseRes.status !== 201) return false;

  // Create execution_states — this INSERT fires the auto_link trigger
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
    no_show_penalty_multiplier: 1.0,
    window_start_utc:           new Date(windowStartTs * 1000).toISOString(),
    window_end_utc:             new Date(windowEndTs   * 1000).toISOString(),
    status:                     'planned',
    created_at_utc:             new Date().toISOString(),
    last_evaluated_at_utc:      new Date().toISOString(),
    status_last_updated_at_utc: new Date().toISOString(),
  }), { headers: HEADERS });

  return stateRes.status === 201;
}

function getShadowStatus(shadowId) {
  const res = http.get(
    `${REST_BASE}/shadow_executions?id=eq.${shadowId}&select=status,reconciled_execution_id`,
    { headers: HEADERS },
  );
  try {
    const rows = JSON.parse(res.body || '[]');
    return rows[0] || null;
  } catch { return null; }
}

function getEvidenceHash(evidenceId) {
  const res = http.get(
    `${REST_BASE}/telegram_evidence_uploads?id=eq.${evidenceId}&select=forensic_hash`,
    { headers: HEADERS },
  );
  try {
    const rows = JSON.parse(res.body || '[]');
    return rows[0]?.forensic_hash || null;
  } catch { return null; }
}

function countShadowTransitions(shadowId) {
  const res = http.get(
    `${REST_BASE}/shadow_execution_transitions?shadow_id=eq.${shadowId}&select=id`,
    { headers: HEADERS },
  );
  try { return JSON.parse(res.body || '[]').length; } catch { return -1; }
}

// ── Scenario: Auto-Link ────────────────────────────────────────────────────────
// Creates orphan evidence → shadow → retroactive execution → verifies auto-link.
export function autolinkScenario() {
  const chatId    = 200_000_000 + __VU;
  const messageId = 300_000_000 + __VU;
  const setId     = `fluid-fsm-${__VU}-${makeUUID().slice(0, 8)}`;

  // Evidence timestamp: 1 hour ago (will be covered by retroactive trip window)
  const messageTs    = Math.floor(Date.now() / 1000) - 3600;
  const windowStart  = messageTs - 1800; // 30 min before evidence
  const windowEnd    = messageTs + 1800; // 30 min after evidence

  group('step_1_create_orphan_evidence', () => {
    const ev = createEvidenceRow(chatId, messageId, messageTs);
    check(ev, { 'evidence created': e => e !== null && e.id !== undefined });
    if (!ev) return;

    const shadowId = createShadowExecution(ev.id, chatId, messageTs);
    check(shadowId, { 'shadow created': s => s !== null });
    if (!shadowId) return;

    // Verify initial state: UNLINKED_SHADOW
    const initialState = getShadowStatus(shadowId);
    check(initialState, {
      'initial status is UNLINKED_SHADOW': s => s?.status === 'UNLINKED_SHADOW',
    });

    group('step_2_create_retroactive_execution', () => {
      const t0 = Date.now();
      const created = createRetroactiveExecution(setId, windowStart, windowEnd);
      autolinkLatency.add(Date.now() - t0);

      check(created, { 'retroactive execution created': c => c === true });

      if (!created) return;

      // Brief pause — trigger fires synchronously, but give DB time to commit
      sleep(1.0);

      group('step_3_verify_autolink', () => {
        const finalState = getShadowStatus(shadowId);

        // PRIMARY ASSERTION: shadow must be RECONCILED
        const linked = finalState?.status === 'RECONCILED' &&
                       finalState?.reconciled_execution_id === setId;
        autolinkRate.add(linked ? 1 : 0);

        if (!linked) {
          console.error(
            `AUTO-LINK FAILED: VU=${__VU} shadow=${shadowId} status=${finalState?.status} ` +
            `reconciled_execution_id=${finalState?.reconciled_execution_id} (expected ${setId})`
          );
          console.log(`Debug: finalState=${JSON.stringify(finalState)}`);
        }

        check(finalState, {
          'shadow status = RECONCILED':              s => s?.status === 'RECONCILED',
          'reconciled_execution_id = trip set_id':   s => s?.reconciled_execution_id === setId,
        });

        // HASH IMMUTABILITY: forensic_hash must not have changed (INV-9)
        const currentHash = getEvidenceHash(ev.id);
        if (currentHash !== ev.forensicHash) {
          hashCollisions.add(1);
          console.error(
            `HASH COLLISION: evidence=${ev.id} hash changed from ${ev.forensicHash} to ${currentHash}`
          );
        }
        check(null, {
          'forensic_hash unchanged after auto-link': () => currentHash === ev.forensicHash,
        });

        // TRANSITION AUDIT: exactly 1 transition row (INV-3)
        const transCount = countShadowTransitions(shadowId);
        if (transCount > 1) duplicateShadows.add(transCount - 1);

        check(null, {
          'exactly 1 shadow transition row': () => transCount === 1,
        });
      });
    });
  });
}

// ── Scenario: Concurrent Auto-Link ────────────────────────────────────────────
// Multiple retroactive trips created simultaneously covering the same shadow window.
// Only one should reconcile the shadow — the others must hit the CAS guard.
export function concurrentAutolinkScenario() {
  const chatId    = 400_000_000 + __VU;
  const messageId = 500_000_000 + __VU;

  const messageTs   = Math.floor(Date.now() / 1000) - 3600;
  const windowStart = messageTs - 1800;
  const windowEnd   = messageTs + 1800;

  // Create the orphan evidence + shadow first
  const ev       = createEvidenceRow(chatId, messageId, messageTs);
  if (!ev) return;
  const shadowId = createShadowExecution(ev.id, chatId, messageTs);
  if (!shadowId) return;

  // Create 3 retroactive executions concurrently — all cover the same window
  const setIds = Array.from({ length: 3 }, (_, i) =>
    `concurrent-${__VU}-${i}-${makeUUID().slice(0, 6)}`
  );

  // Concurrent trip inserts — the trigger fires on each INSERT
  // The FOR UPDATE SKIP LOCKED in the trigger ensures only 1 reconciles
  const requests = setIds.map(sid => ({
    method:  'POST',
    url:     `${REST_BASE}/execution_states`,
    headers: HEADERS,
    body:    JSON.stringify({
      id:                         makeUUID(),
      set_id:                     sid,
      organization_id:            ORG_ID,
      contract_id:                CONTRACT_ID,
      plan_version:               1,
      start_latitude:             -23.5505,
      start_longitude:            -46.6333,
      start_radius_meters:        200,
      contractual_value_cents:    100_00,
      no_show_penalty_multiplier: 1.0,
      window_start_utc:           new Date(windowStart * 1000).toISOString(),
      window_end_utc:             new Date(windowEnd   * 1000).toISOString(),
      status:                     'planned',
      created_at_utc:             new Date().toISOString(),
      last_evaluated_at_utc:      new Date().toISOString(),
      status_last_updated_at_utc: new Date().toISOString(),
    }),
  }));

  http.batch(requests);

  sleep(0.5);

  // Verify: shadow reconciled exactly once (not 3 times)
  const finalState = getShadowStatus(shadowId);
  const transCount = countShadowTransitions(shadowId);

  const reconciled = finalState?.status === 'RECONCILED';
  autolinkRate.add(reconciled ? 1 : 0);

  if (transCount > 1) {
    duplicateShadows.add(transCount - 1);
    console.error(
      `CONCURRENT AUTO-LINK BREACH: shadow=${shadowId} has ${transCount} reconciliation transitions!`
    );
  }

  check(finalState, {
    'concurrent: shadow eventually RECONCILED': s => s?.status === 'RECONCILED',
  });
  check(null, {
    'concurrent: exactly 1 reconciliation transition': () => transCount === 1,
  });
}

// ── Summary ────────────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const linkRate    = data.metrics['fluid_fsm_autolink_success_rate']?.values?.rate ?? 0;
  const hashCol     = data.metrics['fluid_fsm_hash_collision_count']?.values?.count ?? 0;
  const dupShadow   = data.metrics['fluid_fsm_duplicate_shadow_count']?.values?.count ?? 0;
  const latP95      = data.metrics['fluid_fsm_autolink_latency_ms']?.values?.['p(95)'] ?? 'N/A';

  const linkPass = linkRate === 1 ? '✅ PASS' : `❌ FAIL (rate=${(linkRate * 100).toFixed(1)}%)`;

  const tddStatus = linkRate < 0.5
    ? '🔴 TDD GATE: FAILING (expected BEFORE migration — apply 20260702000002_shadow_autolink_trigger.sql)'
    : linkRate === 1
      ? '🟢 TDD GATE: PASSING (migration applied correctly)'
      : '🟡 TDD GATE: PARTIAL (check trigger logic)';

  const report = [
    '=================================================================',
    ' VeraProb Phase 10.3 — Fluid FSM Shadow Auto-Link (INV-11)',
    '=================================================================',
    '',
    ` ${tddStatus}`,
    '',
    ' INVARIANTS TESTED:',
    ` Auto-link success rate: ${(linkRate * 100).toFixed(1)}%   ${linkPass}`,
    ` Hash collisions (INV-9): ${hashCol}   ${hashCol === 0 ? '✅ PASS' : '❌ FAIL'}`,
    ` Duplicate shadows (INV-15): ${dupShadow}   ${dupShadow === 0 ? '✅ PASS' : '❌ FAIL'}`,
    ` Auto-link trigger latency p95: ${typeof latP95 === 'number' ? latP95.toFixed(1) : latP95} ms`,
    '',
    ' TDD WORKFLOW:',
    '   1. Run this test → expect FAIL (auto_link_success_rate == 0)',
    '   2. supabase db push (applies 20260702000002_shadow_autolink_trigger.sql)',
    '   3. Run this test → expect PASS (auto_link_success_rate == 1)',
    '',
    ' VERIFICATION SQL:',
    "   SELECT se.id, se.status, se.reconciled_execution_id,",
    "          se.reconciled_at_utc, es.window_start_utc, es.window_end_utc",
    "   FROM shadow_executions se",
    "   LEFT JOIN execution_states es ON es.set_id = se.reconciled_execution_id",
    "   WHERE se.status = 'RECONCILED'",
    "     AND se.reconciled_at_utc > NOW() - INTERVAL '10 minutes'",
    "   ORDER BY se.reconciled_at_utc DESC;",
    '   -- Expected: all test shadows show status=RECONCILED with correct trip set_id',
    '=================================================================',
  ].join('\n');

  console.log(report);
  return {
    'stdout': report + '\n',
    'docs/governance/k6_fluid_fsm_autolink_results.json': JSON.stringify(data, null, 2),
  };
}
