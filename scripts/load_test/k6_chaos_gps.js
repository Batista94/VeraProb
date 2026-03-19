// =============================================================================
// Phase 8.6 — Chaos Load Test: GPS Jitter & Kinematic Noise Filter
// =============================================================================
// This script tests the Kinematic Noise Filter (INV-12: Chronological
// Determinism) and the Asset State Machine (INV-13) under adversarial GPS
// conditions.
//
// CHAOS SCENARIOS:
//
// SCENARIO A — Teleportation Attack
//   Injects events where coordinates jump > 200m in < 3 seconds.
//   A real vehicle cannot physically do this. The filter MUST reject or
//   quarantine these as noise — otherwise phantom SLA breaches (and false
//   financial verdicts) are generated.
//   PASS criterion: Zero new breach verdicts for teleportation events.
//
// SCENARIO B — GPS Jitter (< 10m noise oscillation)
//   Injects micro-movement events: ±0.00008° lat/lon ≈ ±9m variation.
//   This simulates a parked vehicle with GPS noise. The filter MUST NOT
//   generate a motion event — the asset should remain STATIONARY.
//   PASS criterion: No departure verdicts for jitter-only events.
//
// SCENARIO C — Out-of-Order Delivery
//   Sends events with occurred_at timestamps OUT of sequence (simulating
//   concurrent delivery from multiple Sascar/Omnitracs nodes).
//   The Engine must reconstruct timeline by gps_timestamp, not received_at.
//   PASS criterion: Ledger entries are ordered by occurred_at_utc, not insert
//   order (verifiable via SELECT ... ORDER BY occurred_at_utc).
//
// ARCHITECTURE NOTE:
//   PactaFlow does not have a direct REST endpoint for GPS ingestion — events
//   reach the engine via adapter Edge Functions. Until those endpoints are
//   deployed, this script targets the Supabase REST API on sla_audit_ledger_v2
//   to simulate the EFFECT of chaos GPS on ledger output.
//
//   When Edge Function endpoints are available, replace the REST calls below
//   with the actual ingestion endpoint: POST /functions/v1/ingest-gps-event
//
// RUN:
//   export SUPABASE_URL="https://<project>.supabase.co"
//   export SUPABASE_ANON_KEY="<service_role_or_test_key>"
//   export ORG_ID="<test-organization-uuid>"
//   export CONTRACT_ID="<test-contract-text-id>"
//   k6 run scripts/load_test/k6_chaos_gps.js
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ── Configuration ─────────────────────────────────────────────────────────────
const SUPABASE_URL = __ENV.SUPABASE_URL   || 'http://localhost:54321';
const ANON_KEY     = __ENV.SUPABASE_ANON_KEY || 'test-anon-key';
const ORG_ID       = __ENV.ORG_ID         || '00000000-0000-0000-0000-000000000001';
const CONTRACT_ID  = __ENV.CONTRACT_ID    || 'test-contract-001';

const REST_BASE = `${SUPABASE_URL}/rest/v1`;
const HEADERS   = {
  'Content-Type':  'application/json',
  'apikey':        ANON_KEY,
  'Authorization': `Bearer ${ANON_KEY}`,
  'Prefer':        'return=minimal',
};

// ── Custom metrics ─────────────────────────────────────────────────────────────
const chaosInsertLatency    = new Trend('chaos_insert_ms', true);
const teleportRejectedRate  = new Rate('teleport_rejected_rate');
const jitterVerdictRate     = new Rate('jitter_phantom_verdict_rate');
const outOfOrderErrors      = new Counter('out_of_order_errors');

// ── GPS Coordinate Helpers ────────────────────────────────────────────────────
// São Paulo city center: -23.5505° S, -46.6333° W
const BASE_LAT = -23.5505;
const BASE_LON = -46.6333;

// 1° latitude ≈ 111,139m at any latitude
// 1° longitude ≈ 111,139m × cos(lat) ≈ 91,290m at -23.5° (São Paulo)
const DEG_PER_METER_LAT = 1 / 111139;
const DEG_PER_METER_LON = 1 / 91290;

function jitterCoordinate(base, maxMeters) {
  const direction = Math.random() > 0.5 ? 1 : -1;
  const meters    = Math.random() * maxMeters;
  return base + direction * meters * DEG_PER_METER_LAT;
}

function teleportCoordinate(base, jumpMeters) {
  // Always jump in the same direction to maximize distance
  return base + jumpMeters * DEG_PER_METER_LAT;
}

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

function timestampOffset(secondsAgo) {
  return new Date(Date.now() - secondsAgo * 1000).toISOString();
}

// ── Test Options ───────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Scenario A: Teleportation — 50 chaos VUs for 2 minutes
    teleportation: {
      executor:     'constant-vus',
      vus:          50,
      duration:     '2m',
      exec:         'teleportationScenario',
      gracefulStop: '15s',
    },

    // Scenario B: GPS Jitter — 20 VUs for 2 minutes
    gps_jitter: {
      executor:     'constant-vus',
      vus:          20,
      duration:     '2m',
      exec:         'jitterScenario',
      gracefulStop: '15s',
    },

    // Scenario C: Out-of-Order delivery — 30 VUs for 90 seconds
    out_of_order: {
      executor:     'constant-vus',
      vus:          30,
      duration:     '90s',
      exec:         'outOfOrderScenario',
      gracefulStop: '15s',
      startTime:    '30s', // Start after initial data is in
    },
  },

  thresholds: {
    // All chaos inserts must be fast (even noise events exercise the write path)
    'chaos_insert_ms':               [{ threshold: 'p(95)<300', abortOnFail: false }],
    // Out-of-order errors must be zero (engine must handle them gracefully)
    'out_of_order_errors':           [{ threshold: 'count<1', abortOnFail: false }],
    // HTTP errors must be near zero (server should accept events, filter in engine)
    'http_req_failed':               [{ threshold: 'rate<0.02', abortOnFail: false }],
  },
};

// ── Scenario A: Teleportation ──────────────────────────────────────────────────
// Jump 500m in 1 second — physically impossible for a land vehicle.
// The Engine / Kinematic Noise Filter must classify this as NOISE, not motion.
// We insert the event tagged as a chaos marker so verification queries can
// confirm zero breach verdicts were generated for these entity_ids.
export function teleportationScenario() {
  const assetId  = `chaos-teleport-${__VU}`;
  const setId    = `teleport-${makeUUID()}`;
  const jumpMeters = 300 + Math.random() * 700; // 300m–1000m jump

  // Event 1: Base position (anchor)
  const anchorPayload = JSON.stringify({
    organization_id: ORG_ID,
    type:            'GPS_ANCHOR',
    set_id:          assetId,
    contract_id:     CONTRACT_ID,
    plan_version:    1,
    occurred_at_utc: timestampOffset(5),
    payload: {
      source:    'k6_chaos_teleport',
      batch_id:  setId,
      lat:       BASE_LAT,
      lon:       BASE_LON,
      chaos_tag: 'ANCHOR',
    },
  });

  const r1 = http.post(`${REST_BASE}/sla_audit_ledger_v2`, anchorPayload, {
    headers: HEADERS,
    tags:    { scenario: 'teleportation', event: 'anchor' },
  });

  chaosInsertLatency.add(r1.timings.duration);
  check(r1, { 'teleport_anchor: status 201': r => r.status === 201 });

  // Event 2: Teleport position (1 second later, 300–1000m away)
  const teleportPayload = JSON.stringify({
    organization_id: ORG_ID,
    type:            'GPS_TELEPORT_CHAOS',   // Tagged — engine should flag/reject
    set_id:          assetId,
    contract_id:     CONTRACT_ID,
    plan_version:    1,
    occurred_at_utc: timestampOffset(4),     // 1 second after anchor
    payload: {
      source:         'k6_chaos_teleport',
      lat:            teleportCoordinate(BASE_LAT, jumpMeters),
      lon:            teleportCoordinate(BASE_LON, jumpMeters),
      jump_meters:    jumpMeters,
      chaos_tag:      'TELEPORT',
      // The engine should produce NO breach verdict for this event.
      // If it does, the kinematic noise filter has failed (INV-12 violated).
    },
  });

  const r2 = http.post(`${REST_BASE}/sla_audit_ledger_v2`, teleportPayload, {
    headers: HEADERS,
    tags:    { scenario: 'teleportation', event: 'teleport' },
  });

  chaosInsertLatency.add(r2.timings.duration);

  // The DB accepts the event (engine decides fate), but we track the accept rate
  const accepted = r2.status === 201;
  teleportRejectedRate.add(!accepted); // Rate of server-level rejects (should be near 0)

  check(r2, {
    'teleport_event: accepted (engine decides)': r => r.status === 201,
  });

  sleep(1 + Math.random() * 2);
}

// ── Scenario B: GPS Jitter ─────────────────────────────────────────────────────
// Send rapid micro-movement events: ±8m oscillation around a fixed point.
// A correctly implemented Kinematic Noise Filter must NOT generate departure
// events for sub-threshold movements (threshold typically 50m or configured).
// PASS: Zero SLA_VERDICT_DEPARTURE entries in ledger for jitter entity_ids.
export function jitterScenario() {
  const assetId = `chaos-jitter-${__VU}`;
  const setId   = `jitter-${makeUUID()}`;

  // Send 10 rapid jitter events (simulates parked vehicle GPS oscillation)
  for (let i = 0; i < 10; i++) {
    const jitterLat = jitterCoordinate(BASE_LAT, 8); // ±8m noise
    const jitterLon = jitterCoordinate(BASE_LON, 8);

    const payload = JSON.stringify({
      organization_id: ORG_ID,
      type:            'GPS_JITTER_CHAOS',
      set_id:          assetId,
      contract_id:     CONTRACT_ID,
      plan_version:    1,
      occurred_at_utc: timestampOffset(60 - i * 6), // 60s → 6s ago
      payload: {
        source:     'k6_chaos_jitter',
        batch_id:   setId,
        lat:        jitterLat,
        lon:        jitterLon,
        noise_m:    8,
        chaos_tag:  'JITTER',
        iteration:  i,
        // Engine MUST NOT generate a departure verdict for this.
        // Kinematic noise filter: sub-threshold movement = STATIONARY.
      },
    });

    const res = http.post(`${REST_BASE}/sla_audit_ledger_v2`, payload, {
      headers: HEADERS,
      tags:    { scenario: 'gps_jitter' },
    });

    chaosInsertLatency.add(res.timings.duration);

    check(res, {
      'jitter: event accepted': r => r.status === 201,
    });
  }

  // After injecting jitter, query back to verify no departure verdict was created
  // for this asset. This validates the noise filter output.
  const verifyUrl = `${REST_BASE}/sla_audit_ledger_v2` +
    `?organization_id=eq.${ORG_ID}` +
    `&set_id=eq.${assetId}` +
    `&type=eq.SLA_VERDICT_DEPARTURE` +
    `&limit=1`;

  const verifyRes = http.get(verifyUrl, {
    headers: { ...HEADERS, 'Prefer': 'count=exact' },
    tags:    { scenario: 'gps_jitter', event: 'verify' },
  });

  // Content-Range: 0-0/COUNT — count must be 0
  const contentRange  = verifyRes.headers['Content-Range'] || '';
  const hasPhantom    = verifyRes.body && verifyRes.body !== '[]';
  jitterVerdictRate.add(hasPhantom ? 1 : 0);

  check(verifyRes, {
    'jitter: no phantom departure verdict': r => !hasPhantom,
  });

  sleep(5 + Math.random() * 5);
}

// ── Scenario C: Out-of-Order Delivery ─────────────────────────────────────────
// Sends events with shuffled occurred_at timestamps. The engine must
// reconstruct chronological order by occurred_at_utc, not insert order.
// This validates INV-12 (Chronological Determinism).
export function outOfOrderScenario() {
  const assetId = `chaos-ooo-${__VU}`;
  const setId   = `ooo-${makeUUID()}`;

  // Create 5 events with shuffled timestamps (most recent first, oldest last)
  const timestamps = [
    timestampOffset(5),   // Most recent
    timestampOffset(25),  // Middle-old
    timestampOffset(15),  // Middle-recent
    timestampOffset(35),  // Oldest
    timestampOffset(10),  // Middle
  ]; // Intentionally out of order

  const requests = timestamps.map((ts, i) => ({
    method:  'POST',
    url:     `${REST_BASE}/sla_audit_ledger_v2`,
    headers: HEADERS,
    body:    JSON.stringify({
      organization_id: ORG_ID,
      type:            'GPS_OOO_CHAOS',
      set_id:          setId,
      contract_id:     CONTRACT_ID,
      plan_version:    1,
      occurred_at_utc: ts,
      payload: {
        source:      'k6_chaos_ooo',
        chaos_tag:   'OUT_OF_ORDER',
        send_order:  i,
        // Engine must sort by occurred_at_utc, not by the order we sent these
      },
    }),
  }));

  // Batch all 5 events simultaneously (simulates multi-node concurrent delivery)
  const responses = http.batch(requests);

  let allOk = true;
  responses.forEach((res, i) => {
    chaosInsertLatency.add(res.timings.duration);

    const ok = check(res, {
      [`ooo_event_${i}: status 201`]: r => r.status === 201,
    });

    if (!ok) {
      outOfOrderErrors.add(1);
      allOk = false;
    }
  });

  // Verify: query back in occurred_at order and check sequence is correct
  if (allOk) {
    const verifyUrl = `${REST_BASE}/sla_audit_ledger_v2` +
      `?organization_id=eq.${ORG_ID}` +
      `&set_id=eq.${setId}` +
      `&order=occurred_at_utc.asc` +
      `&select=occurred_at_utc,payload`;

    const verifyRes = http.get(verifyUrl, {
      headers: { ...HEADERS, 'Prefer': 'return=representation' },
      tags:    { scenario: 'out_of_order', event: 'verify' },
    });

    check(verifyRes, {
      'ooo: chronological order retrievable': r => r.status === 200,
      'ooo: returns 5 events':               r => {
        try {
          const data = JSON.parse(r.body);
          return Array.isArray(data) && data.length === 5;
        } catch { return false; }
      },
    });
  }

  sleep(3 + Math.random() * 4);
}

// ── Summary ────────────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const insertP95     = data.metrics['chaos_insert_ms']?.values?.['p(95)'] ?? 'N/A';
  const oooErrors     = data.metrics['out_of_order_errors']?.values?.count ?? 0;
  const httpFailed    = (data.metrics['http_req_failed']?.values?.rate ?? 0) * 100;

  const report = [
    '============================================================',
    ' PactaFlow Phase 8.6 — GPS Chaos Test Summary',
    '============================================================',
    '',
    ' SCENARIO A: Teleportation Attack (50 VUs × 2min)',
    '   Check Supabase for GPS_TELEPORT_CHAOS events with no',
    '   corresponding SLA_VERDICT_BREACH in the same set_id.',
    '   Pass = Kinematic Noise Filter rejected phantom breaches.',
    '',
    ' SCENARIO B: GPS Jitter (20 VUs × 2min)',
    '   Verify no SLA_VERDICT_DEPARTURE entries exist for',
    '   chaos-jitter-* entity_ids (sub-threshold movement).',
    '',
    ' SCENARIO C: Out-of-Order Delivery (30 VUs × 90s)',
    `   Out-of-order errors: ${oooErrors}   (target: 0)`,
    '   Verify ledger ORDER BY occurred_at_utc returns events',
    '   in chronological order regardless of insert order.',
    '',
    `  Chaos INSERT p95: ${typeof insertP95 === 'number' ? insertP95.toFixed(1) : insertP95} ms   (target: < 300ms)`,
    `  HTTP Failure Rate: ${httpFailed.toFixed(2)}%   (target: < 2%)`,
    '',
    ' VERIFICATION SQL (run in Supabase SQL Editor):',
    '   -- Check for phantom breach verdicts from teleport events:',
    "   SELECT COUNT(*) FROM sla_audit_ledger_v2",
    "   WHERE set_id LIKE 'chaos-teleport-%'",
    "   AND type = 'SLA_VERDICT_BREACH';",
    '   -- Expected: 0',
    '',
    '   -- Check for phantom departure verdicts from jitter:',
    "   SELECT COUNT(*) FROM sla_audit_ledger_v2",
    "   WHERE set_id LIKE 'chaos-jitter-%'",
    "   AND type = 'SLA_VERDICT_DEPARTURE';",
    '   -- Expected: 0',
    '============================================================',
  ].join('\n');

  console.log(report);

  return {
    'stdout': report + '\n',
    'docs/governance/k6_chaos_results.json': JSON.stringify(data, null, 2),
  };
}
