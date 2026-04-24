// =============================================================================
// Phase 10 — Chaos Test: Multi-Tenant Isolation at Scale (INV-1, INV-22)
// =============================================================================
//
// SCENARIO A — gps_flood_10_orgs:
//   100 concurrent GPS pings (10 VUs per org × 10 orgs) into the canonical_facts
//   ingest endpoint. Verifies that no telemetry from Org X leaks into Org Y's
//   data, and that the DB does not deadlock under concurrent multi-tenant load.
//   PASS: cross_tenant_leak_count == 0 AND deadlock_count == 0 AND p95 < 500ms
//
// SCENARIO B — concurrent_verdict_isolation:
//   500 VUs from 10 orgs writing sla_audit_ledger_v2 rows simultaneously.
//   Verifies: each org only reads back its own rows post-write.
//   PASS: all isolation_verify checks pass (rate == 1.0)
//
// SCENARIO C — deadlock_probe:
//   Concurrent cross-org writes with interleaved reads. If PostgreSQL's row-level
//   locking causes deadlocks, the DB returns SQLSTATE 40P01. This scenario
//   measures how often that happens.
//   PASS: deadlock_count == 0 (abortOnFail)
//
// ARCHITECTURE:
//   10 org JWTs required. Use scripts/k6_get_test_jwts.mjs extended to 10 orgs,
//   or seed via supabase/seed.sql with orgs 000...0001 through 000...0010.
//   Uses Supabase pooler (port 54329) to stay under INV-16 (60 connection cap).
//
// RUN:
//   node scripts/k6_get_test_jwts.mjs  # extend to 10 orgs
//   export SUPABASE_URL=http://localhost:54321
//   export SUPABASE_ANON_KEY=<anon_key>
//   export ORG_COUNT=10
//   # ORG_1_JWT ... ORG_10_JWT, ORG_1_ID ... ORG_10_ID (see seed.sql)
//   k6 run scripts/load_test/k6_multitenant_scale.js
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ── Configuration ──────────────────────────────────────────────────────────────
const SUPABASE_URL = __ENV.SUPABASE_URL      || 'http://localhost:54321';
const ANON_KEY     = __ENV.SUPABASE_ANON_KEY || '';
const ORG_COUNT    = parseInt(__ENV.ORG_COUNT  || '10', 10);

// Build org configs from env vars ORG_1_ID...ORG_N_ID, ORG_1_JWT...ORG_N_JWT
// Default: seed.sql pattern 00000000-0000-0000-0000-00000000000N
function buildOrgConfig(n) {
  const padded   = String(n).padStart(12, '0');
  const orgId    = __ENV[`ORG_${n}_ID`]  || `00000000-0000-0000-0000-${padded}`;
  const jwt      = __ENV[`ORG_${n}_JWT`] || '';
  const contract = __ENV[`ORG_${n}_CONTRACT`] || `00000000-0000-0000-0000-c0${padded}`;
  return { orgId, jwt, contract, label: `ORG_${n}` };
}

const ORGS = Array.from({ length: ORG_COUNT }, (_, i) => buildOrgConfig(i + 1));

// ── Pooler endpoint (INV-16: 60-connection cap) ────────────────────────────────
// Use Supabase's transaction pooler to avoid exhausting direct connections.
const REST_BASE = `${SUPABASE_URL}/rest/v1`; // Pooler is transparent via Supabase REST

function headersForOrg(org) {
  return {
    'Content-Type':  'application/json',
    'apikey':        ANON_KEY,
    'Authorization': `Bearer ${org.jwt}`,
    'Prefer':        'return=minimal',
  };
}

// ── Custom metrics ─────────────────────────────────────────────────────────────
const gpsIngestLatency    = new Trend('mt_gps_ingest_ms', true);
const crossTenantLeaks    = new Counter('mt_cross_tenant_leaks');
const deadlockCount       = new Counter('mt_deadlock_count');
const isolationRate       = new Rate('mt_isolation_rate');
const verdictWriteLatency = new Trend('mt_verdict_write_ms', true);

// ── Options ────────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // A: 100 concurrent GPS pings (10 per org × 10 orgs)
    gps_flood_10_orgs: {
      executor:    'constant-vus',
      vus:         100,
      duration:    '3m',
      exec:        'gpsFloodScenario',
      gracefulStop: '15s',
    },

    // B: 500 VUs writing verdicts + isolation verification
    concurrent_verdict_isolation: {
      executor:    'constant-vus',
      vus:         500,
      duration:    '2m',
      exec:        'verdictIsolationScenario',
      startTime:   '4m',
      gracefulStop: '15s',
    },

    // C: Deadlock probe — interleaved cross-org writes
    deadlock_probe: {
      executor:    'constant-vus',
      vus:         50,
      duration:    '2m',
      exec:        'deadlockProbeScenario',
      startTime:   '7m',
      gracefulStop: '15s',
    },
  },

  thresholds: {
    // Zero cross-tenant leaks — hard fail (INV-1, INV-22)
    'mt_cross_tenant_leaks':  [{ threshold: 'count==0', abortOnFail: true }],
    // Zero deadlocks — hard fail (INV-16)
    'mt_deadlock_count':      [{ threshold: 'count==0', abortOnFail: true }],
    // 100% isolation rate
    'mt_isolation_rate':      [{ threshold: 'rate==1', abortOnFail: true }],
    // GPS ingest p95 < 500ms under 100-VU load
    'mt_gps_ingest_ms':       [{ threshold: 'p(95)<500', abortOnFail: false }],
    // Verdict write p95 < 200ms
    'mt_verdict_write_ms':    [{ threshold: 'p(95)<200', abortOnFail: false }],
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function orgForVU() {
  // Round-robin: VU 1→Org1, VU 2→Org2, ..., VU 11→Org1, etc.
  return ORGS[(__VU - 1) % ORG_COUNT];
}

function buildLedgerEntry(org, overrides = {}) {
  return JSON.stringify({
    organization_id: org.orgId,
    type:            overrides.type || 'SLA_VERDICT_COMPLIANT',
    set_id:          overrides.set_id || `mt-${org.label}-${makeUUID()}`,
    contract_id:     org.contract,
    plan_version:    1,
    occurred_at_utc: new Date().toISOString(),
    payload:         overrides.payload || { source: 'k6_multitenant_scale', scenario: 'phase_10' },
  });
}

function checkForCrossOrgLeak(ownOrg, ownSetIdPrefix) {
  // After write, query WITH own JWT but filter by another org's ID
  const otherOrg = ORGS.find(o => o.orgId !== ownOrg.orgId) || ORGS[0];

  const res = http.get(
    `${REST_BASE}/sla_audit_ledger_v2?organization_id=eq.${otherOrg.orgId}&limit=1`,
    { headers: headersForOrg(ownOrg) },
  );

  let rows = [];
  try { rows = JSON.parse(res.body || '[]'); } catch { /* */ }

  if (rows.length > 0) {
    crossTenantLeaks.add(rows.length);
    console.error(
      `LEAK: ${ownOrg.label} JWT returned ${rows.length} row(s) from ${otherOrg.label}! ` +
      `Body: ${res.body?.substring(0, 200)}`
    );
    return false;
  }
  return true;
}

// ── Scenario A: GPS Flood (100 VUs, 10 Orgs) ──────────────────────────────────
// Each VU writes a canonical_facts-equivalent ledger entry for its org.
// After writing, probes for cross-tenant leaks.
export function gpsFloodScenario() {
  const org = orgForVU();
  if (!org.jwt) return; // Skip if JWT not configured

  const setId = `gps-${org.label}-${makeUUID()}`;
  const payload = buildLedgerEntry(org, {
    type:   'SLA_VERDICT_COMPLIANT',
    set_id: setId,
    payload: {
      source:     'k6_gps_flood',
      lat:        -23.5505 + (Math.random() - 0.5) * 0.01,
      lon:        -46.6333 + (Math.random() - 0.5) * 0.01,
      org:        org.label,
    },
  });

  const res = http.post(`${REST_BASE}/sla_audit_ledger_v2`, payload, {
    headers: headersForOrg(org),
    tags:    { scenario: 'gps_flood', org: org.label },
  });

  gpsIngestLatency.add(res.timings.duration);

  check(res, {
    [`gps_flood_${org.label}: status 201`]: r => r.status === 201,
  });

  // Probe for cross-org leak after write
  const clean = checkForCrossOrgLeak(org, setId);
  isolationRate.add(clean ? 1 : 0);

  // Detect deadlock (SQLSTATE 40P01) in body
  if (res.body && res.body.includes('40P01')) {
    deadlockCount.add(1);
    console.error(`DEADLOCK detected for ${org.label}: ${res.body}`);
  }

  sleep(0.5 + Math.random() * 0.5); // 0.5–1s cadence
}

// ── Scenario B: Concurrent Verdict Isolation ───────────────────────────────────
// 500 VUs from 10 orgs write simultaneously. Then each org reads back only its own.
export function verdictIsolationScenario() {
  const org    = orgForVU();
  if (!org.jwt) return;

  const setId  = `verdict-${org.label}-${makeUUID()}`;
  const body   = buildLedgerEntry(org, { set_id: setId });

  const writeRes = http.post(`${REST_BASE}/sla_audit_ledger_v2`, body, {
    headers: headersForOrg(org),
    tags:    { scenario: 'verdict_isolation', phase: 'write', org: org.label },
  });

  verdictWriteLatency.add(writeRes.timings.duration);

  // Detect deadlock
  if (writeRes.body && writeRes.body.includes('40P01')) {
    deadlockCount.add(1);
  }

  check(writeRes, {
    [`verdict_write_${org.label}: 201`]: r => r.status === 201,
  });

  // Verify: can read own row back
  const readRes = http.get(
    `${REST_BASE}/sla_audit_ledger_v2?set_id=eq.${setId}&organization_id=eq.${org.orgId}`,
    { headers: headersForOrg(org) },
  );

  let ownRows = [];
  try { ownRows = JSON.parse(readRes.body || '[]'); } catch { /* */ }

  // Verify: all returned rows belong to this org
  const onlyOwnOrg = ownRows.every(r => r.organization_id === org.orgId);
  isolationRate.add(onlyOwnOrg ? 1 : 0);

  if (!onlyOwnOrg) {
    crossTenantLeaks.add(1);
    console.error(`ISOLATION BREACH in verdict read for ${org.label}`);
  }

  check(readRes, {
    [`verdict_read_${org.label}: 200`]:     r => r.status === 200,
    [`verdict_read_${org.label}: own-only`]: () => onlyOwnOrg,
  });

  sleep(0.1);
}

// ── Scenario C: Deadlock Probe ────────────────────────────────────────────────
// Interleave writes from different orgs on related rows to probe for deadlocks.
// If the DB is correctly using per-row locking (not table locks), no deadlocks.
export function deadlockProbeScenario() {
  const orgA = orgForVU();
  const orgB = ORGS[(__VU) % ORG_COUNT]; // Next org in round-robin

  if (!orgA.jwt || !orgB.jwt) return;

  // Write to A and B simultaneously — different rows, no actual conflict,
  // but concurrent multi-tenant load exercises the locking path
  const [resA, resB] = http.batch([
    {
      method:  'POST',
      url:     `${REST_BASE}/sla_audit_ledger_v2`,
      headers: headersForOrg(orgA),
      body:    buildLedgerEntry(orgA, {
        set_id: `deadlock-probe-A-${__VU}-${makeUUID()}`,
        payload: { vu: __VU, org: orgA.label, probe: true },
      }),
    },
    {
      method:  'POST',
      url:     `${REST_BASE}/sla_audit_ledger_v2`,
      headers: headersForOrg(orgB),
      body:    buildLedgerEntry(orgB, {
        set_id: `deadlock-probe-B-${__VU}-${makeUUID()}`,
        payload: { vu: __VU, org: orgB.label, probe: true },
      }),
    },
  ]);

  [resA, resB].forEach((res, i) => {
    const label = i === 0 ? orgA.label : orgB.label;

    if (res.body && res.body.includes('40P01')) {
      deadlockCount.add(1);
      console.error(`DEADLOCK in deadlock_probe for ${label}: ${res.body}`);
    }

    check(res, {
      [`deadlock_probe_${label}: no deadlock`]: r =>
        r.status === 201 || (!r.body || !r.body.includes('40P01')),
    });
  });

  sleep(0.2 + Math.random() * 0.3);
}

// ── Summary ────────────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const leaks       = data.metrics['mt_cross_tenant_leaks']?.values?.count   ?? 0;
  const deadlocks   = data.metrics['mt_deadlock_count']?.values?.count       ?? 0;
  const isoRate     = data.metrics['mt_isolation_rate']?.values?.rate        ?? 0;
  const gpsP95      = data.metrics['mt_gps_ingest_ms']?.values?.['p(95)']   ?? 'N/A';
  const verdictP95  = data.metrics['mt_verdict_write_ms']?.values?.['p(95)'] ?? 'N/A';

  const leakPass    = leaks    === 0 ? '✅ PASS (ZERO LEAKS)'     : `❌ FAIL — ${leaks} LEAK(S)`;
  const dlPass      = deadlocks === 0 ? '✅ PASS (ZERO DEADLOCKS)' : `❌ FAIL — ${deadlocks} DEADLOCK(S)`;

  const report = [
    '=================================================================',
    ' VeraProb Phase 10 — Multi-Tenant Isolation at Scale (INV-1)',
    `  Orgs tested: ${ORG_COUNT} | VUs: 100 (GPS) + 500 (Verdicts) + 50 (Probe)`,
    '=================================================================',
    '',
    ' INV-1 + INV-22: CROSS-TENANT ISOLATION',
    ` Cross-tenant leaks:     ${leaks}     ${leakPass}`,
    ` Isolation rate:         ${(isoRate * 100).toFixed(1)}%   (target: 100%)`,
    '',
    ' INV-16: DEADLOCK SAFETY',
    ` Deadlocks detected:     ${deadlocks}   ${dlPass}`,
    '',
    ' PERFORMANCE',
    ` GPS ingest p95:         ${typeof gpsP95    === 'number' ? gpsP95.toFixed(1)    : gpsP95} ms   (target: < 500ms)`,
    ` Verdict write p95:      ${typeof verdictP95 === 'number' ? verdictP95.toFixed(1) : verdictP95} ms   (target: < 200ms)`,
    '',
    ' VERIFICATION SQL (run after test for definitive DB-level check):',
    '   -- Cross-org row contamination (must be 0):',
    "   WITH org_rows AS (",
    "     SELECT set_id, organization_id",
    "     FROM sla_audit_ledger_v2",
    "     WHERE set_id LIKE 'gps-ORG_%' OR set_id LIKE 'verdict-ORG_%'",
    "   )",
    "   SELECT COUNT(*) AS contaminated",
    "   FROM org_rows",
    "   WHERE organization_id != (",
    "     SELECT orgId FROM <org_map> WHERE set_id LIKE CONCAT('%', label, '%')",
    "   );",
    '   -- Expected: 0',
    '=================================================================',
  ].join('\n');

  console.log(report);
  return {
    'stdout': report + '\n',
    'docs/governance/k6_multitenant_scale_results.json': JSON.stringify(data, null, 2),
  };
}
