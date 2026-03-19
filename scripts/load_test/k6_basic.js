// =============================================================================
// Phase 8.6 — Load Test: Basic Steady State + Bulk Flood
// =============================================================================
// Targets the SLA Audit Ledger v2 (the primary write-heavy table in the
// multi-tenant architecture). Two scenarios:
//
// SCENARIO 1 — Steady State (1,000 vehicles × 1 event/min)
//   Simulates normal production load: 1,000 concurrent VUs, each inserting
//   1 ledger verdict per minute ≈ ~16.7 inserts/sec sustained throughput.
//   Threshold: p95 INSERT < 200ms
//
// SCENARIO 2 — Bulk Flood (1 worker, 200 retroactive events in 2 seconds)
//   Simulates a vehicle emerging from a tunnel: 200 accumulated GPS events
//   burst-fired simultaneously with retroactive occurred_at timestamps.
//   Tests chronological determinism (INV-12) under burst load.
//   Threshold: p95 INSERT < 500ms (relaxed for burst)
//
// SCENARIO 3 — Ledger Read (OCC dashboard query)
//   Simulates 50 concurrent dispatcher reads on the ledger with org+entity
//   composite filter. Tests the index efficiency.
//   Threshold: p95 SELECT < 500ms
//
// RUN:
//   export SUPABASE_URL="https://<project>.supabase.co"
//   export SUPABASE_ANON_KEY="<service_role_or_test_key>"
//   export ORG_ID="<test-organization-uuid>"
//   export CONTRACT_ID="<test-contract-text-id>"
//   k6 run scripts/load_test/k6_basic.js
//
// NOTE: Use a DEDICATED test organization (not production). The ledger is
// append-only (INV-1) — test rows cannot be deleted. Use a throwaway org.
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// ── Configuration ─────────────────────────────────────────────────────────────
const SUPABASE_URL   = __ENV.SUPABASE_URL   || 'http://localhost:54321';
const ANON_KEY       = __ENV.SUPABASE_ANON_KEY || 'test-anon-key';
const ORG_ID         = __ENV.ORG_ID         || '00000000-0000-0000-0000-000000000001';
const CONTRACT_ID    = __ENV.CONTRACT_ID    || 'test-contract-001';

const REST_BASE = `${SUPABASE_URL}/rest/v1`;

const HEADERS = {
  'Content-Type':  'application/json',
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ANON_KEY}`,
  'Prefer':        'return=minimal',
};

// ── Custom metrics ─────────────────────────────────────────────────────────────
const insertLatency = new Trend('ledger_insert_p95_ms', true);
const selectLatency = new Trend('ledger_select_p95_ms', true);
const insertErrors  = new Counter('ledger_insert_errors');
const selectErrors  = new Counter('ledger_select_errors');

// ── Thresholds ─────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Scenario 1: 1,000 VUs × 1 event/min (sustained production load)
    steady_state: {
      executor:          'constant-vus',
      vus:               1000,
      duration:          '5m',
      exec:              'steadyStateScenario',
      gracefulStop:      '30s',
    },

    // Scenario 2: Bulk flood — 1 VU × 200 events in 2 seconds
    bulk_flood: {
      executor:          'per-vu-iterations',
      vus:               1,
      iterations:        200,
      maxDuration:       '30s',
      exec:              'bulkFloodScenario',
      // Start after steady state to avoid overlap on connection pool
      startTime:         '5m30s',
    },

    // Scenario 3: OCC ledger reads (50 concurrent dispatchers)
    ledger_read: {
      executor:          'constant-vus',
      vus:               50,
      duration:          '3m',
      exec:              'ledgerReadScenario',
      startTime:         '30s',   // Overlap with steady state to test combined load
    },
  },

  thresholds: {
    // INV-1 write path must be < 200ms at p95 under sustained load
    'ledger_insert_p95_ms': [{ threshold: 'p(95)<200', abortOnFail: false }],
    // OCC reads must be < 500ms at p95
    'ledger_select_p95_ms': [{ threshold: 'p(95)<500', abortOnFail: false }],
    // HTTP-level checks
    'http_req_failed':      [{ threshold: 'rate<0.01', abortOnFail: false }],
    // Overall p95 across all HTTP calls
    'http_req_duration':    [{ threshold: 'p(95)<500', abortOnFail: false }],
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeUUID() {
  // Fast UUID v4 approximation for k6 (no crypto module in k6)
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function retroactiveOccurredAt(secondsAgo) {
  const ts = new Date(Date.now() - secondsAgo * 1000);
  return ts.toISOString();
}

function buildLedgerEntry(overrides = {}) {
  return JSON.stringify({
    organization_id: ORG_ID,
    type:            overrides.type            || 'SLA_VERDICT_COMPLIANT',
    set_id:          overrides.set_id          || `set-${makeUUID()}`,
    contract_id:     overrides.contract_id     || CONTRACT_ID,
    plan_version:    overrides.plan_version    || 1,
    payload:         overrides.payload         || { source: 'k6_load_test', engine_version: '8.6' },
    occurred_at_utc: overrides.occurred_at_utc || new Date().toISOString(),
  });
}

// ── Scenario 1: Steady State ───────────────────────────────────────────────────
// Each VU inserts 1 event then sleeps ~57s to simulate 1 event/min cadence.
export function steadyStateScenario() {
  const payload = buildLedgerEntry({ type: 'SLA_VERDICT_COMPLIANT' });

  const res = http.post(`${REST_BASE}/sla_audit_ledger_v2`, payload, {
    headers: HEADERS,
    tags:    { scenario: 'steady_state' },
  });

  insertLatency.add(res.timings.duration);

  const ok = check(res, {
    'steady_state: insert status 201': r => r.status === 201,
    'steady_state: no error body':     r => !r.body || r.body.length < 100 || !r.body.includes('"error"'),
  });

  if (!ok) insertErrors.add(1);

  // Sleep to simulate 1 event per minute per vehicle
  // 5m test duration / 60s sleep ≈ 5 events per VU per scenario run
  sleep(57 + Math.random() * 6); // 57–63s jitter to avoid thundering-herd
}

// ── Scenario 2: Bulk Flood ─────────────────────────────────────────────────────
// 200 retroactive events burst-fired — simulates tunnel reconnection.
// Events are ordered retroactively (occurred_at going backwards) to test
// chronological determinism (INV-12).
export function bulkFloodScenario() {
  // Each iteration is one of the 200 burst events.
  // iteration index available via __VU (always 1 here) and __ITER
  const secondsAgo = 1200 - (__ITER % 200) * 6; // 20 min ago → recent, 6s steps

  const payload = buildLedgerEntry({
    type:            'SLA_VERDICT_BREACH',
    set_id:          `flood-set-${makeUUID()}`,
    occurred_at_utc: retroactiveOccurredAt(secondsAgo),
    payload: {
      source:           'k6_bulk_flood',
      seconds_retroactive: secondsAgo,
      iter:             __ITER,
    },
  });

  const res = http.post(`${REST_BASE}/sla_audit_ledger_v2`, payload, {
    headers: HEADERS,
    tags:    { scenario: 'bulk_flood' },
  });

  insertLatency.add(res.timings.duration);

  const ok = check(res, {
    'bulk_flood: insert status 201': r => r.status === 201,
    'bulk_flood: latency < 500ms':   r => r.timings.duration < 500,
  });

  if (!ok) insertErrors.add(1);

  // No sleep — maximum burst rate
}

// ── Scenario 3: Ledger Read (OCC Dashboard) ────────────────────────────────────
// Simulates a dispatcher's OCC screen polling the ledger for a contract.
// Tests the composite index: (organization_id, set_id) on sla_audit_ledger_v2.
export function ledgerReadScenario() {
  group('occ_ledger_read', () => {
    const url = `${REST_BASE}/sla_audit_ledger_v2` +
      `?organization_id=eq.${ORG_ID}` +
      `&order=occurred_at_utc.desc` +
      `&limit=50`;

    const res = http.get(url, {
      headers: { ...HEADERS, 'Prefer': 'count=estimated' },
      tags:    { scenario: 'ledger_read' },
    });

    selectLatency.add(res.timings.duration);

    const ok = check(res, {
      'ledger_read: status 200':      r => r.status === 200,
      'ledger_read: returns array':   r => r.body && r.body.startsWith('['),
      'ledger_read: latency < 500ms': r => r.timings.duration < 500,
    });

    if (!ok) selectErrors.add(1);
  });

  sleep(2 + Math.random() * 3); // OCC polls every 2–5s
}

// ── Summary handler ────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const insertP95  = data.metrics['ledger_insert_p95_ms']?.values?.['p(95)'] ?? 'N/A';
  const selectP95  = data.metrics['ledger_select_p95_ms']?.values?.['p(95)'] ?? 'N/A';
  const failRate   = data.metrics['http_req_failed']?.values?.rate ?? 0;
  const insertErrs = data.metrics['ledger_insert_errors']?.values?.count ?? 0;

  const report = [
    '============================================================',
    ' veraprob Phase 8.6 — Basic Load Test Summary',
    '============================================================',
    '',
    ' SCENARIO: Steady State (1,000 VUs × 1 GPS event/min)',
    ` Ledger INSERT p95:  ${typeof insertP95 === 'number' ? insertP95.toFixed(1) : insertP95} ms   (target: < 200ms)`,
    ` Insert errors:      ${insertErrs}`,
    '',
    ' SCENARIO: OCC Read (50 VUs polling ledger)',
    ` Ledger SELECT p95:  ${typeof selectP95 === 'number' ? selectP95.toFixed(1) : selectP95} ms   (target: < 500ms)`,
    '',
    ' SCENARIO: Bulk Flood (200 retroactive events in burst)',
    ' (See bulk_flood tagged metrics in k6 output above)',
    '',
    ` HTTP Failure Rate:  ${(failRate * 100).toFixed(2)}%   (target: < 1%)`,
    '',
    ' NEXT: Review Connection Pool usage in Supabase Dashboard.',
    ' Free Tier limit: 60 connections. Peak must not exceed 50.',
    '============================================================',
  ].join('\n');

  console.log(report);

  return {
    'stdout': report + '\n',
    'docs/governance/k6_basic_results.json': JSON.stringify(data, null, 2),
  };
}
