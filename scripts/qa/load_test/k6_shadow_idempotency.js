// =============================================================================
// Phase 10 -- Chaos Test: Shadow Recovery & Crash Resilience (INV-11)
// =============================================================================
//
// DESIGN NOTE (Advisor fix applied):
// This script bypasses the telegram-webhook edge function and inserts directly
// into telegram_evidence_uploads via service-role REST. The webhook's Telegram
// file-download path cannot be exercised without a live bot token and real file_ids.
// The invariant under test lives entirely in the DB:
//   UNIQUE (chat_id, telegram_message_id) -- uq_teu_chat_message
// That constraint is correctly and completely tested via direct DB INSERT.
//
// SCENARIO A -- concurrent_duplicate_ingestion:
//   10 VUs each fire 5 identical direct DB inserts with the same
//   (chat_id, telegram_message_id). Only 1 row must survive in
//   telegram_evidence_uploads and at most 1 row in shadow_executions.
//   PASS: duplicate_evidence_rows == 0 AND duplicate_shadow_rows == 0
//
// SCENARIO B -- retry_after_delay:
//   Insert 1 row, wait 3s (Telegram retry window), insert identical row again.
//   uq_teu_chat_message must absorb the retry across time.
//   PASS: same idempotency criteria as A.
//
// SCENARIO C -- rapid_burst:
//   30 VUs each fire 3 rapid identical inserts. High-concurrency ON CONFLICT path.
//
// NOTE: The SIGKILL crash simulation is handled by scripts/chaos/crash_recovery.sh.
//
// RUN:
//   export SUPABASE_URL=http://localhost:54321
//   export SERVICE_ROLE_KEY=<service_role_key>
//   export ORG_ID=00000000-0000-0000-0000-000000000001
//   export DRIVER_ID=<driver_uuid_in_drivers_table_for_test_org>
//   export BOUND_CHAT_ID=100000001
//   k6 run scripts/load_test/k6_shadow_idempotency.js
// =============================================================================

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const SUPABASE_URL     = __ENV.SUPABASE_URL     || 'http://localhost:54321';
const SERVICE_ROLE_KEY = __ENV.SERVICE_ROLE_KEY || '';
const ORG_ID           = __ENV.ORG_ID           || '00000000-0000-0000-0000-000000000001';
// Driver UUID must exist in public.drivers for the test org (FK constraint on telegram_evidence_uploads).
// Get it with: SELECT id FROM drivers WHERE organization_id = '<ORG_ID>' LIMIT 1;
const DRIVER_ID    = __ENV.DRIVER_ID    || '00000000-0000-0000-0000-000000000099';
const BOUND_CHAT_ID = parseInt(__ENV.BOUND_CHAT_ID || '100000001', 10);

const REST_BASE = `${SUPABASE_URL}/rest/v1`;

const HEADERS_SVC = {
  'Content-Type':  'application/json',
  'apikey':        SERVICE_ROLE_KEY,
  'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  'Prefer':        'return=minimal',
};

// -- Custom metrics ------------------------------------------------------------
const ingestLatency     = new Trend('shadow_ingest_ms', true);
const duplicateEvidence = new Counter('shadow_duplicate_evidence_rows');
const duplicateShadows  = new Counter('shadow_duplicate_shadow_rows');
const idempotencyRate   = new Rate('shadow_idempotency_rate');

// -- Options -------------------------------------------------------------------
export const options = {
  scenarios: {
    concurrent_duplicate_ingestion: {
      executor:     'per-vu-iterations',
      vus:          10,
      iterations:   1,
      maxDuration:  '3m',
      exec:         'concurrentDuplicateScenario',
      gracefulStop: '15s',
    },
    retry_after_delay: {
      executor:     'per-vu-iterations',
      vus:          20,
      iterations:   1,
      maxDuration:  '3m',
      exec:         'retryAfterDelayScenario',
      startTime:    '3m30s',
      gracefulStop: '15s',
    },
    rapid_burst: {
      executor:     'constant-vus',
      vus:          30,
      duration:     '2m',
      exec:         'rapidBurstScenario',
      startTime:    '7m',
      gracefulStop: '15s',
    },
  },
  thresholds: {
    'shadow_duplicate_evidence_rows': [{ threshold: 'count==0', abortOnFail: true }],
    'shadow_duplicate_shadow_rows':   [{ threshold: 'count==0', abortOnFail: true }],
    'shadow_idempotency_rate':        [{ threshold: 'rate==1', abortOnFail: true }],
    'shadow_ingest_ms':               [{ threshold: 'p(95)<500', abortOnFail: false }],
  },
};

// -- Helpers -------------------------------------------------------------------

function makeUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

// Exact schema (after all migrations applied to telegram_evidence_uploads):
//   organization_id, driver_id, chat_id, telegram_message_id,
//   file_name, forensic_hash (64 hex chars), storage_path, source,
//   linked_set_id, telegram_message_date, requires_manual_link,
//   mime_type, clock_drift_seconds
function buildEvidencePayload(messageId, chatId) {
  // 64-char fake hash: stable per (messageId, chatId) so retries are truly identical
  const hashBase = String(messageId) + String(chatId);
  const forensicHash = hashBase.padStart(64, '0').slice(-64);
  return JSON.stringify({
    organization_id:       ORG_ID,
    driver_id:             DRIVER_ID,
    chat_id:               chatId,
    telegram_message_id:   messageId,
    file_name:             makeUUID() + '.jpg',
    forensic_hash:         forensicHash,
    storage_path:          ORG_ID + '/telegram/' + chatId + '/' + makeUUID() + '.jpg',
    source:                'telegram',
    linked_set_id:         null,
    telegram_message_date: new Date().toISOString(),
    requires_manual_link:  true,
    mime_type:             'image/jpeg',
    clock_drift_seconds:   0,
  });
}

function countEvidenceRows(chatId, messageId) {
  const res = http.get(
    REST_BASE + '/telegram_evidence_uploads?chat_id=eq.' + chatId +
    '&telegram_message_id=eq.' + messageId + '&select=id',
    { headers: Object.assign({}, HEADERS_SVC, { 'Prefer': 'count=exact' }) }
  );
  try { return JSON.parse(res.body || '[]').length; } catch (_) { return -1; }
}

function countShadowRows(chatId, messageId) {
  const evRes = http.get(
    REST_BASE + '/telegram_evidence_uploads?chat_id=eq.' + chatId +
    '&telegram_message_id=eq.' + messageId + '&select=id',
    { headers: HEADERS_SVC }
  );
  let ids = [];
  try { ids = JSON.parse(evRes.body || '[]').map(function(r) { return r.id; }); } catch (_) { return -1; }
  if (ids.length === 0) return 0;
  const shRes = http.get(
    REST_BASE + '/shadow_executions?origin_evidence_id=in.(' + ids.join(',') + ')&select=id',
    { headers: HEADERS_SVC }
  );
  try { return JSON.parse(shRes.body || '[]').length; } catch (_) { return -1; }
}

// -- Scenario A: Concurrent Duplicate Ingestion --------------------------------
// 10 VUs each fire 5 identical INSERT requests with same (chat_id, message_id).
// Tests: uq_teu_chat_message absorbs all duplicates via ON CONFLICT DO NOTHING.
export function concurrentDuplicateScenario() {
  var messageId = 900000000 + __VU;
  var reqs = [];
  for (var i = 0; i < 5; i++) {
    reqs.push({
      method:  'POST',
      url:     REST_BASE + '/telegram_evidence_uploads',
      headers: Object.assign({}, HEADERS_SVC, { 'Prefer': 'return=minimal' }),
      body:    buildEvidencePayload(messageId, BOUND_CHAT_ID),
    });
  }

  var start = Date.now();
  var responses = http.batch(reqs);
  ingestLatency.add(Date.now() - start);

  responses.forEach(function(res, i) {
    check(res, { ['concurrent_dup[' + i + ']: no 500']: function(r) { return r.status < 500; } });
  });

  sleep(0.5);
  var evCount = countEvidenceRows(BOUND_CHAT_ID, messageId);
  var shCount = countShadowRows(BOUND_CHAT_ID, messageId);
  var ok = evCount <= 1 && shCount <= 1;
  idempotencyRate.add(ok ? 1 : 0);

  if (evCount > 1) {
    duplicateEvidence.add(evCount - 1);
    console.error('IDEMPOTENCY BREACH: uq_teu_chat_message failed -- chat=' + BOUND_CHAT_ID +
      ' msg=' + messageId + ' has ' + evCount + ' rows (expected <= 1)');
  }
  if (shCount > 1) {
    duplicateShadows.add(shCount - 1);
    console.error('SHADOW DUPLICATE: ' + shCount + ' rows for msg=' + messageId);
  }

  check(null, {
    'concurrent_dup: evid<=1': function() { return evCount <= 1; },
    'concurrent_dup: shad<=1': function() { return shCount <= 1; },
  });
}

// -- Scenario B: Retry After Delay ---------------------------------------------
// Insert -> wait 3s -> identical insert. uq_teu_chat_message must absorb retry.
export function retryAfterDelayScenario() {
  var messageId = 800000000 + __VU;

  group('first_insert', function() {
    var res = http.post(
      REST_BASE + '/telegram_evidence_uploads',
      buildEvidencePayload(messageId, BOUND_CHAT_ID),
      { headers: Object.assign({}, HEADERS_SVC, { 'Prefer': 'return=minimal' }) }
    );
    ingestLatency.add(res.timings.duration);
    check(res, { 'first_insert: 201': function(r) { return r.status === 201; } });
  });

  sleep(3);

  group('retry_insert', function() {
    var res = http.post(
      REST_BASE + '/telegram_evidence_uploads',
      buildEvidencePayload(messageId, BOUND_CHAT_ID),
      { headers: Object.assign({}, HEADERS_SVC, { 'Prefer': 'return=minimal' }) }
    );
    ingestLatency.add(res.timings.duration);
    check(res, { 'retry_insert: no 500': function(r) { return r.status < 500; } });
  });

  sleep(0.5);
  var evCount = countEvidenceRows(BOUND_CHAT_ID, messageId);
  var shCount = countShadowRows(BOUND_CHAT_ID, messageId);
  var ok = evCount <= 1 && shCount <= 1;
  idempotencyRate.add(ok ? 1 : 0);

  if (evCount > 1) duplicateEvidence.add(evCount - 1);
  if (shCount > 1) duplicateShadows.add(shCount - 1);

  check(null, {
    'retry: evid<=1 after delay': function() { return evCount <= 1; },
    'retry: shad<=1 after delay': function() { return shCount <= 1; },
  });
}

// -- Scenario C: Rapid Burst ---------------------------------------------------
// 30 VUs each fire 3 rapid identical inserts. Stresses concurrent ON CONFLICT path.
export function rapidBurstScenario() {
  var messageId = 700000000 + __VU;

  for (var i = 0; i < 3; i++) {
    var res = http.post(
      REST_BASE + '/telegram_evidence_uploads',
      buildEvidencePayload(messageId, BOUND_CHAT_ID),
      { headers: Object.assign({}, HEADERS_SVC, { 'Prefer': 'return=minimal' }) }
    );
    ingestLatency.add(res.timings.duration);
    var idx = i;
    check(res, { ['burst[' + idx + ']: no 500']: function(r) { return r.status < 500; } });
    sleep(0.1);
  }

  sleep(0.5);
  var evCount = countEvidenceRows(BOUND_CHAT_ID, messageId);
  var shCount = countShadowRows(BOUND_CHAT_ID, messageId);
  var ok = evCount <= 1 && shCount <= 1;
  idempotencyRate.add(ok ? 1 : 0);

  if (evCount > 1) duplicateEvidence.add(evCount - 1);
  if (shCount > 1) duplicateShadows.add(shCount - 1);

  check(null, {
    'burst: evid<=1': function() { return evCount <= 1; },
    'burst: shad<=1': function() { return shCount <= 1; },
  });
}

// -- Summary -------------------------------------------------------------------
export function handleSummary(data) {
  var dupEv     = (data.metrics['shadow_duplicate_evidence_rows'] || {values:{count:0}}).values.count;
  var dupSh     = (data.metrics['shadow_duplicate_shadow_rows']   || {values:{count:0}}).values.count;
  var idemRate  = (data.metrics['shadow_idempotency_rate']        || {values:{rate:0}}).values.rate;
  var ingestP95 = ((data.metrics['shadow_ingest_ms'] || {}).values || {})['p(95)'] || 'N/A';

  var evPass = dupEv === 0 ? 'PASS' : 'FAIL -- ' + dupEv + ' duplicate(s)';
  var shPass = dupSh === 0 ? 'PASS' : 'FAIL -- ' + dupSh + ' duplicate(s)';

  var report = [
    '=================================================================',
    ' VeraProb Phase 10 -- Shadow Recovery & Crash Resilience (INV-11)',
    '=================================================================',
    '',
    ' IDEMPOTENCY GUARD: uq_teu_chat_message + uq_se_evidence',
    ' Duplicate evidence rows: ' + dupEv + '   ' + evPass,
    ' Duplicate shadow rows:   ' + dupSh + '   ' + shPass,
    ' Overall idempotency rate: ' + (idemRate * 100).toFixed(1) + '%   (target: 100%)',
    ' Ingest latency p95: ' + (typeof ingestP95 === 'number' ? ingestP95.toFixed(1) : ingestP95) + ' ms',
    '',
    ' CRASH SIMULATION:',
    '   Run scripts/chaos/crash_recovery.sh for the SIGKILL + retry test.',
    '   That script kills the edge-runtime container mid-request and verifies',
    '   that Telegram retry produces no duplicate rows.',
    '',
    ' VERIFICATION SQL:',
    '   -- Evidence idempotency check (must return 0 rows with count > 1):',
    "   SELECT chat_id, telegram_message_id, COUNT(*) AS cnt",
    "   FROM telegram_evidence_uploads",
    "   WHERE telegram_message_id BETWEEN 700000000 AND 900999999",
    "   GROUP BY 1, 2 HAVING COUNT(*) > 1;",
    '',
    '   -- Shadow idempotency check:',
    "   SELECT origin_evidence_id, COUNT(*) AS cnt",
    "   FROM shadow_executions",
    "   GROUP BY 1 HAVING COUNT(*) > 1;",
    '   -- Both queries: expected 0 rows',
    '=================================================================',
  ].join('\n');

  console.log(report);
  return {
    'stdout': report + '\n',
    'docs/governance/k6_shadow_idempotency_results.json': JSON.stringify(data, null, 2),
  };
}
