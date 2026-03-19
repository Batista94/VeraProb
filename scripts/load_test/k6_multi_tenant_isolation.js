// =============================================================================
// Phase 8.7 — Multi-Tenant Isolation Stress Test
// =============================================================================
// Validates two properties simultaneously:
//
// PROPERTY 1 — RLS OVERHEAD (INV-6: MULTI-TENANT + RLS)
//   Goal: RLS policy evaluation adds < 5ms overhead to same-org queries.
//   Method: Compare baseline same-org SELECT latency vs. cross-org probe latency.
//   The delta between them approximates the RLS predicate cost when the
//   policy filters to zero rows (maximum evaluation load with no index shortcut).
//
// PROPERTY 2 — CROSS-TENANT DATA ISOLATION (INV-6 + INV-10)
//   Goal: Zero cross-tenant data leaks under concurrent mixed-org load.
//   Method: Org B JWT explicitly requests Org A's data via REST API.
//   RLS must return an empty array (not an error, not Org A's rows).
//
// SCENARIOS:
//   1. baseline_read      — 50 VUs, Org A reads own ledger (p95 SELECT baseline)
//   2. cross_tenant_probe — 10 VUs, Org B JWT probes Org A data (must get [])
//   3. mixed_org_write    — 500 VUs (250 Org A + 250 Org B) concurrent inserts
//   4. isolation_verify   — After mixed writes: each org reads back only its own data
//
// RUN (use o helper para obter os JWTs automaticamente):
//   node scripts/k6_get_test_jwts.mjs   # imprime o bloco de export
//   # copie e cole o output, depois:
//   k6 run scripts/load_test/k6_multi_tenant_isolation.js
//
// Env vars necessários:
//   SUPABASE_URL      — ex: http://localhost:54321
//   SUPABASE_ANON_KEY — anon key (mesmo para os dois orgs; autenticação via Bearer)
//   ORG_A_JWT         — access_token do admin-a@pactaflow.dev (injeta org_id no JWT)
//   ORG_B_JWT         — access_token do admin-b@pactaflow.dev
//   ORG_A_ID          — UUID da Org A (seed: 00000000-0000-0000-0000-000000000001)
//   ORG_B_ID          — UUID da Org B (seed: 00000000-0000-0000-0000-000000000002)
//   CONTRACT_A_ID     — UUID do contrato Org A (seed: 00000000-0000-0000-0000-ca0000000001)
//   CONTRACT_B_ID     — UUID do contrato Org B (seed: 00000000-0000-0000-0000-cb0000000001)
//
// Use organizações de teste dedicadas — o ledger é append-only (INV-1).
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// ── Configuration ─────────────────────────────────────────────────────────────
// UUIDs padrão alinhados com supabase/seed.sql (funciona sem env vars após db reset)
const SUPABASE_URL   = __ENV.SUPABASE_URL      || 'http://localhost:54321';
const ANON_KEY       = __ENV.SUPABASE_ANON_KEY || '';  // obrigatório — use k6_get_test_jwts.mjs
const ORG_A_JWT      = __ENV.ORG_A_JWT         || '';  // obrigatório — use k6_get_test_jwts.mjs
const ORG_B_JWT      = __ENV.ORG_B_JWT         || '';  // obrigatório — use k6_get_test_jwts.mjs
const ORG_A_ID       = __ENV.ORG_A_ID          || '00000000-0000-0000-0000-000000000001';
const ORG_B_ID       = __ENV.ORG_B_ID          || '00000000-0000-0000-0000-000000000002';
const CONTRACT_A_ID  = __ENV.CONTRACT_A_ID     || '00000000-0000-0000-0000-ca0000000001';
const CONTRACT_B_ID  = __ENV.CONTRACT_B_ID     || '00000000-0000-0000-0000-cb0000000001';

const REST_BASE = `${SUPABASE_URL}/rest/v1`;

// ── JWT-scoped headers ────────────────────────────────────────────────────────
// IMPORTANTE: Supabase REST exige dois headers distintos:
//   apikey:        SEMPRE a anon key (mesma para todos) — permite acesso à API
//   Authorization: Bearer <user_jwt> — determina a identidade RLS
// Usar o JWT do usuário como apikey quebraria a autenticação.
const HEADERS_ORG_A = {
  'Content-Type':  'application/json',
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ORG_A_JWT}`,
  'Prefer':        'return=minimal',
};

const HEADERS_ORG_B = {
  'Content-Type':  'application/json',
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ORG_B_JWT}`,
  'Prefer':        'return=minimal',
};

// ── Custom metrics ─────────────────────────────────────────────────────────────
const baselineSelectLatency = new Trend('rls_baseline_select_ms', true);
const crossTenantLatency    = new Trend('rls_cross_tenant_select_ms', true);
const mixedWriteLatency     = new Trend('rls_mixed_write_ms', true);
const leakDetected          = new Counter('cross_tenant_leak_count');
const isolationErrors       = new Counter('isolation_errors');
const crossTenantEmpty      = new Rate('cross_tenant_returns_empty');

// ── Thresholds ─────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Scenario 1: Org A reads own data — establishes SELECT latency baseline
    baseline_read: {
      executor:     'constant-vus',
      vus:          50,
      duration:     '3m',
      exec:         'baselineReadScenario',
      gracefulStop: '15s',
    },

    // Scenario 2: Org B probes Org A data — tests RLS isolation
    // Starts after 30s to let baseline stabilize
    cross_tenant_probe: {
      executor:     'constant-vus',
      vus:          10,
      duration:     '3m',
      exec:         'crossTenantProbeScenario',
      startTime:    '30s',
      gracefulStop: '15s',
    },

    // Scenario 3: 500 VUs from two orgs writing simultaneously
    // Starts after baseline+probe settle (after 4m)
    mixed_org_write: {
      executor:     'constant-vus',
      vus:          500,
      duration:     '2m',
      exec:         'mixedOrgWriteScenario',
      startTime:    '4m',
      gracefulStop: '15s',
    },

    // Scenario 4: Isolation verification — each org reads back only its own rows
    isolation_verify: {
      executor:     'per-vu-iterations',
      vus:          2,           // VU 1 = Org A, VU 2 = Org B
      iterations:   20,          // 10 reads each
      maxDuration:  '60s',
      exec:         'isolationVerifyScenario',
      startTime:    '6m30s',     // After mixed_org_write completes + buffer
      gracefulStop: '15s',
    },
  },

  thresholds: {
    // Core isolation guarantee: zero cross-tenant leaks (hard fail)
    'cross_tenant_leak_count':      [{ threshold: 'count==0', abortOnFail: true }],

    // RLS overhead target: < 5ms delta between baseline and cross-tenant probe
    // Expressed as: cross-tenant p95 must be < baseline p95 + 5ms
    // Since we can't express relative thresholds in k6, we set absolute targets:
    'rls_baseline_select_ms':       [{ threshold: 'p(95)<500', abortOnFail: false }],
    'rls_cross_tenant_select_ms':   [{ threshold: 'p(95)<505', abortOnFail: false }],
    // (The 5ms gap enforced in handleSummary by computing the delta)

    // Mixed write path under concurrent multi-tenant load
    'rls_mixed_write_ms':           [{ threshold: 'p(95)<200', abortOnFail: false }],

    // Cross-tenant probes must ALWAYS return empty (100% of the time)
    'cross_tenant_returns_empty':   [{ threshold: 'rate==1', abortOnFail: true }],

    // Overall HTTP health
    'http_req_failed':              [{ threshold: 'rate<0.01', abortOnFail: false }],
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function buildEntry(orgId, contractId, overrides = {}) {
  return JSON.stringify({
    organization_id: orgId,
    type:            overrides.type || 'SLA_VERDICT_COMPLIANT',
    set_id:          overrides.set_id || `isolation-test-${makeUUID()}`,
    contract_id:     contractId,
    plan_version:    1,
    occurred_at_utc: new Date().toISOString(),
    payload:         overrides.payload || { source: 'k6_isolation_test', phase: '8.7' },
  });
}

// ── Scenario 1: Baseline Read ──────────────────────────────────────────────────
// Org A reads its own data. Establishes SELECT p95 without cross-tenant pressure.
export function baselineReadScenario() {
  const url = `${REST_BASE}/sla_audit_ledger_v2` +
    `?organization_id=eq.${ORG_A_ID}` +
    `&order=occurred_at_utc.desc` +
    `&limit=50`;

  const res = http.get(url, {
    headers: { ...HEADERS_ORG_A, 'Prefer': 'count=estimated' },
    tags:    { scenario: 'baseline_read', org: 'A' },
  });

  baselineSelectLatency.add(res.timings.duration);

  check(res, {
    'baseline_read: status 200':    r => r.status === 200,
    'baseline_read: returns array': r => r.body && r.body.startsWith('['),
  });

  sleep(1 + Math.random() * 2); // 1–3s polling interval
}

// ── Scenario 2: Cross-Tenant Probe ────────────────────────────────────────────
// Org B's JWT explicitly queries with organization_id = ORG_A_ID.
// RLS MUST enforce that the response is an empty array (never Org A's rows).
// The query will be intercepted by:
//   USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
// which will never match ORG_A_ID when authenticated as Org B.
export function crossTenantProbeScenario() {
  // Attempt to read Org A's data using Org B's JWT
  const probeUrl = `${REST_BASE}/sla_audit_ledger_v2` +
    `?organization_id=eq.${ORG_A_ID}` +   // Explicitly requesting Org A's data
    `&order=occurred_at_utc.desc` +
    `&limit=10`;

  const res = http.get(probeUrl, {
    headers: { ...HEADERS_ORG_B, 'Prefer': 'count=exact' },
    tags:    { scenario: 'cross_tenant_probe', org: 'B_probing_A' },
  });

  crossTenantLatency.add(res.timings.duration);

  // The response MUST be an empty array — RLS silently filters to []
  const body = res.body || '[]';
  let parsed = [];
  try { parsed = JSON.parse(body); } catch (_) { /* invalid JSON counts as error */ }

  const isEmpty = Array.isArray(parsed) && parsed.length === 0;
  const status200 = res.status === 200;

  crossTenantEmpty.add(isEmpty ? 1 : 0);

  // If we received any rows, that's a critical data leak — increment counter
  if (!isEmpty || !status200) {
    leakDetected.add(1);
    console.error(
      `CRITICAL LEAK DETECTED: Org B received ${parsed.length} rows from Org A's ledger!` +
      ` Status: ${res.status}, Body: ${body.substring(0, 200)}`
    );
  }

  check(res, {
    'cross_tenant: status 200':       r => r.status === 200,
    'cross_tenant: no Org A rows':    () => isEmpty,
    'cross_tenant: body is []':       r => r.body === '[]',
  });

  sleep(0.5 + Math.random() * 1); // Rapid probing
}

// ── Scenario 3: Mixed-Org Write ────────────────────────────────────────────────
// 500 VUs split across two organizations (by VU index parity).
// VU 1, 3, 5... → Org A. VU 2, 4, 6... → Org B.
// Tests that concurrent writes from multiple tenants don't interfere.
export function mixedOrgWriteScenario() {
  const isOrgA    = __VU % 2 === 1;
  const orgId     = isOrgA ? ORG_A_ID     : ORG_B_ID;
  const contractId = isOrgA ? CONTRACT_A_ID : CONTRACT_B_ID;
  const headers   = isOrgA ? HEADERS_ORG_A : HEADERS_ORG_B;
  const orgLabel  = isOrgA ? 'A' : 'B';

  const payload = buildEntry(orgId, contractId, {
    set_id:  `mixed-write-${orgLabel}-${makeUUID()}`,
    payload: {
      source:   'k6_mixed_org_write',
      phase:    '8.7',
      org_slot: orgLabel,
      vu:       __VU,
    },
  });

  const res = http.post(`${REST_BASE}/sla_audit_ledger_v2`, payload, {
    headers: headers,
    tags:    { scenario: 'mixed_org_write', org: orgLabel },
  });

  mixedWriteLatency.add(res.timings.duration);

  const ok = check(res, {
    [`mixed_write_org_${orgLabel}: status 201`]: r => r.status === 201,
  });

  if (!ok) isolationErrors.add(1);

  sleep(0.1 + Math.random() * 0.2); // tight cadence to stress isolation
}

// ── Scenario 4: Isolation Verification ────────────────────────────────────────
// VU 1 = Org A, VU 2 = Org B.
// Each org reads back data written by mixed_org_write and verifies
// that NO rows from the other org are visible in the response.
export function isolationVerifyScenario() {
  const isOrgA     = __VU % 2 === 1;
  const ownOrgId   = isOrgA ? ORG_A_ID  : ORG_B_ID;
  const otherOrgId = isOrgA ? ORG_B_ID  : ORG_A_ID;
  const headers    = isOrgA ? HEADERS_ORG_A : HEADERS_ORG_B;
  const orgLabel   = isOrgA ? 'A' : 'B';

  group(`isolation_verify_org_${orgLabel}`, () => {
    // Query own data (should return rows)
    const ownUrl = `${REST_BASE}/sla_audit_ledger_v2` +
      `?organization_id=eq.${ownOrgId}` +
      `&set_id=like.mixed-write-${orgLabel}-*` +
      `&order=occurred_at_utc.desc` +
      `&limit=100`;

    const ownRes = http.get(ownUrl, {
      headers: { ...headers, 'Prefer': 'count=estimated' },
      tags:    { scenario: 'isolation_verify', org: orgLabel, read: 'own' },
    });

    let ownRows = [];
    try { ownRows = JSON.parse(ownRes.body || '[]'); } catch (_) { /* */ }

    check(ownRes, {
      [`verify_${orgLabel}: own data returns 200`]: r => r.status === 200,
      [`verify_${orgLabel}: own data has rows`]:    () => ownRows.length > 0,
    });

    // Verify no other-org rows exist in own data (sanity: all returned org IDs match)
    const ownHasOnlyOwnOrg = ownRows.every(row => row.organization_id === ownOrgId);
    if (!ownHasOnlyOwnOrg) {
      leakDetected.add(1);
      console.error(
        `ISOLATION BREACH: Org ${orgLabel}'s query returned rows from another org!`
      );
    }

    check(null, {
      [`verify_${orgLabel}: all rows belong to own org`]: () => ownHasOnlyOwnOrg,
    });

    // Probe for other org's rows explicitly
    const otherUrl = `${REST_BASE}/sla_audit_ledger_v2` +
      `?organization_id=eq.${otherOrgId}` +
      `&order=occurred_at_utc.desc` +
      `&limit=5`;

    const otherRes = http.get(otherUrl, {
      headers: { ...headers, 'Prefer': 'count=exact' },
      tags:    { scenario: 'isolation_verify', org: orgLabel, read: 'other' },
    });

    let otherRows = [];
    try { otherRows = JSON.parse(otherRes.body || '[]'); } catch (_) { /* */ }

    if (otherRows.length > 0) {
      leakDetected.add(otherRows.length);
      console.error(
        `CRITICAL: Org ${orgLabel} can see ${otherRows.length} rows from the other org!`
      );
    }

    crossTenantEmpty.add(otherRows.length === 0 ? 1 : 0);

    check(null, {
      [`verify_${orgLabel}: cannot see other org rows`]: () => otherRows.length === 0,
    });
  });

  sleep(1);
}

// ── Summary handler ────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const baselineP95    = data.metrics['rls_baseline_select_ms']?.values?.['p(95)'] ?? 'N/A';
  const crossTenantP95 = data.metrics['rls_cross_tenant_select_ms']?.values?.['p(95)'] ?? 'N/A';
  const writeP95       = data.metrics['rls_mixed_write_ms']?.values?.['p(95)'] ?? 'N/A';
  const leakCount      = data.metrics['cross_tenant_leak_count']?.values?.count ?? 0;
  const emptyRate      = data.metrics['cross_tenant_returns_empty']?.values?.rate ?? 0;
  const httpFailed     = (data.metrics['http_req_failed']?.values?.rate ?? 0) * 100;

  const rlsOverheadMs = (typeof baselineP95 === 'number' && typeof crossTenantP95 === 'number')
    ? (crossTenantP95 - baselineP95).toFixed(2)
    : 'N/A (run both scenarios)';

  const rlsOverheadPass = (typeof baselineP95 === 'number' && typeof crossTenantP95 === 'number')
    ? (crossTenantP95 - baselineP95 < 5 ? '✅ PASS' : '❌ FAIL')
    : '—';

  const isolationPass = leakCount === 0 ? '✅ PASS (ZERO LEAKS)' : `❌ FAIL — ${leakCount} LEAK(S) DETECTED`;

  const report = [
    '============================================================',
    ' PactaFlow Phase 8.7 — Multi-Tenant Isolation Test Summary',
    '============================================================',
    '',
    ' INV-6 + INV-10: RLS ISOLATION RESULT',
    ` Cross-tenant leak count: ${leakCount}   ${isolationPass}`,
    ` Cross-tenant queries returning []: ${(emptyRate * 100).toFixed(1)}%   (target: 100%)`,
    '',
    ' RLS OVERHEAD MEASUREMENT',
    ` Baseline SELECT p95 (Org A → own data):   ${typeof baselineP95    === 'number' ? baselineP95.toFixed(1)    : baselineP95} ms`,
    ` Cross-tenant SELECT p95 (Org B → Org A):  ${typeof crossTenantP95 === 'number' ? crossTenantP95.toFixed(1) : crossTenantP95} ms`,
    ` Delta (RLS overhead proxy):               ${rlsOverheadMs} ms   (target: < 5ms)   ${rlsOverheadPass}`,
    '',
    ' MIXED-ORG CONCURRENT WRITE',
    ` Write p95 (500 VUs, 2 orgs concurrent):   ${typeof writeP95 === 'number' ? writeP95.toFixed(1) : writeP95} ms   (target: < 200ms)`,
    '',
    ` HTTP Failure Rate: ${httpFailed.toFixed(2)}%   (target: < 1%)`,
    '',
    ' VERIFICATION SQL (run in Supabase SQL Editor after test):',
    '   -- Cross-tenant data leakage check (must be 0):',
    "   SELECT COUNT(*) AS leak_count",
    "   FROM sla_audit_ledger_v2",
    "   WHERE set_id LIKE 'mixed-write-A-%'",
    "     AND organization_id != '<ORG_A_ID>';",
    '   -- Expected: 0',
    '',
    "   SELECT COUNT(*) AS leak_count",
    "   FROM sla_audit_ledger_v2",
    "   WHERE set_id LIKE 'mixed-write-B-%'",
    "     AND organization_id != '<ORG_B_ID>';",
    '   -- Expected: 0',
    '',
    '   -- RLS overhead via EXPLAIN ANALYZE (run without k6 load):',
    '   EXPLAIN ANALYZE',
    '   SELECT id FROM sla_audit_ledger_v2',
    "   WHERE organization_id = '<ORG_A_ID>'",
    '   ORDER BY occurred_at_utc DESC LIMIT 50;',
    '   -- Look for: Index Scan (not Seq Scan), actual time < 5ms',
    '============================================================',
  ].join('\n');

  console.log(report);

  return {
    'stdout': report + '\n',
    'docs/governance/k6_isolation_results.json': JSON.stringify(data, null, 2),
  };
}
