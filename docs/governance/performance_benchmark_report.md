# VeraProb — Phase 8.6 Performance Benchmark Report

**Status:** Template — populate with actual k6 results after running load tests
**Phase:** 8.6 — Performance & Escala
**Date:** 2026-04-03
**Author:** Tech Lead (Phase 8.6 synthesis)
**Engine Version:** 8.6.0

---

## Executive Summary

Phase 8.6 establishes the performance baseline for VeraProb's EvaluationEngine under production-representative load. The goals are:

| Metric | Target | Status |
|--------|--------|--------|
| Ledger INSERT p95 (steady state) | < 200ms | Pending measurement |
| Ledger SELECT p95 (OCC dashboard) | < 500ms | Pending measurement |
| Bulk flood burst INSERT p95 | < 500ms | Pending measurement |
| HTTP failure rate | < 1% | Pending measurement |
| Supabase connection peak | < 50 / 60 | Pending measurement |
| Phantom penalty rate (jitter) | 0 | Pending measurement |

**Decision on `evaluation_context_cache`:** Deferred — measure JOIN latency under load first. If p95 JOIN latency < 50ms on steady state, the denormalized read-model is unnecessary complexity. See Section 4.

---

## 1. Architecture Constraints

### Supabase Free Tier Hard Limits

| Resource | Limit | Risk Level |
|----------|-------|-----------|
| Concurrent connections | 60 | HIGH — 1,000 VUs will saturate without connection pooling |
| Read replicas | 0 | MEDIUM — OCC reads share write connection pool |
| Realtime channels | 200 concurrent | LOW — OCC uses polling in MVP, not Realtime |
| Storage | 500MB | LOW — ledger is text/JSONB, not binary |

**Mitigation:** k6 runs with `--vus 1000` does NOT mean 1,000 simultaneous DB connections. Each VU sleeps 57–63 seconds between events (1 event/min cadence), so the effective concurrent connection count is:

```
Active connections ≈ VUs × (request_duration / sleep_duration)
≈ 1,000 × (0.1s / 60s) ≈ 1.7 active connections (burst: ~17 during peak)
```

The bulk flood scenario (200 events in 2 seconds) is the real connection stress test.

### Architecture Decisions (per `sla_audit_ledger_v2`)

- **HASH partitioned** by `organization_id` (4 partitions: p0–p3)
- **Composite PK:** `(organization_id, id)` — ensures all inserts for one org route to the same partition
- **Existing indexes:** `(organization_id, timestamp DESC)` and `(organization_id, entity_id)`
- **New indexes (Phase 8.6):** See Section 3

---

## 2. Load Test Results

> **Populate this section after running:**
> ```bash
> k6 run scripts/load_test/k6_basic.js
> k6 run scripts/load_test/k6_chaos_gps.js
> ```

### 2.1 Steady State — 1,000 Vehicles × 1 GPS Event/Min

| Metric | Result | Target | Pass? |
|--------|--------|--------|-------|
| Ledger INSERT p95 | — ms | < 200ms | — |
| Ledger INSERT p99 | — ms | < 500ms | — |
| Ledger INSERT avg | — ms | — | — |
| HTTP failure rate | —% | < 1% | — |
| Peak DB connections | — | < 50 | — |

**k6 command:**
```bash
export SUPABASE_URL="https://<project>.supabase.co"
export SUPABASE_ANON_KEY="<service_role_key>"
export ORG_ID="<test-org-uuid>"
export CONTRACT_ID="<test-contract-id>"
k6 run scripts/load_test/k6_basic.js
```

### 2.2 Bulk Flood — 200 Retroactive Events in 2 Seconds

| Metric | Result | Target | Pass? |
|--------|--------|--------|-------|
| Bulk INSERT p95 | — ms | < 500ms | — |
| All 200 events accepted | — | 100% | — |
| Chronological order preserved | — | Yes | — |

**Chronological Determinism Verification (INV-12):**
```sql
-- After bulk flood, verify events are retrievable in occurred_at order:
SELECT occurred_at_utc, payload->>'iter' AS send_order
FROM sla_audit_ledger_v2
WHERE organization_id = '<org-uuid>'
  AND payload->>'source' = 'k6_bulk_flood'
ORDER BY occurred_at_utc ASC
LIMIT 200;
-- Expected: occurred_at_utc is monotonically increasing (0→199 seconds ago)
-- Regardless of the order rows were physically inserted.
```

### 2.3 OCC Read — 50 Concurrent Dispatcher Reads

| Metric | Result | Target | Pass? |
|--------|--------|--------|-------|
| Ledger SELECT p95 | — ms | < 500ms | — |
| Ledger SELECT p99 | — ms | < 1000ms | — |
| Index Scan used | — | Yes (not Seq Scan) | — |

### 2.4 GPS Chaos — Teleportation & Jitter

| Check | Result | Expected | Pass? |
|-------|--------|----------|-------|
| Phantom breach verdicts (teleport events) | — | 0 | — |
| Phantom departure verdicts (jitter events) | — | 0 | — |
| Out-of-order delivery errors | — | 0 | — |
| Chaos INSERT p95 | — ms | < 300ms | — |

**Phantom Penalty Verification SQL:**
```sql
-- A. No breach verdicts from teleportation chaos events
SELECT COUNT(*) AS phantom_breaches
FROM sla_audit_ledger_v2
WHERE entity_id LIKE 'chaos-teleport-%'
  AND type = 'SLA_VERDICT_BREACH';
-- Expected: 0

-- B. No departure verdicts from GPS jitter events
SELECT COUNT(*) AS phantom_departures
FROM sla_audit_ledger_v2
WHERE entity_id LIKE 'chaos-jitter-%'
  AND type = 'SLA_VERDICT_DEPARTURE';
-- Expected: 0
```

---

## 3. Index Audit (Phase 8.6 Migration)

Migration file: `supabase/migrations/20260403000004_performance_indexes.sql`

### Indexes Added

| Index | Table | Columns | Type | Rationale |
|-------|-------|---------|------|-----------|
| `idx_sla_ledger_contract_type_time` | `sla_audit_ledger` | `(contract_id, type, occurred_at_utc DESC)` | B-tree | Engine verdict queries by contract + type + time |
| `idx_sla_ledger_v2_org_entity_time` | `sla_audit_ledger_v2` | `(organization_id, entity_id, timestamp DESC)` | B-tree | OCC timeline — enables Index Only Scan |
| `idx_contracts_org_active_window` | `contracts` | `(organization_id, valid_from_utc, valid_until_utc)` WHERE `status='active'` | Partial B-tree | Engine active-contract date-window lookup |
| `idx_invitations_org_pending` | `invitations` | `(organization_id, created_at_utc DESC)` WHERE `status='pending'` | Partial B-tree | Admin invitation list — pending only |
| `idx_plan_declarations_contract_version` | `plan_declarations` | `(contract_fk, plan_version DESC)` | B-tree | Replaces single-column; enables Index Only Scan |
| `idx_audit_packages_org_sealed_time` | `audit_packages` | `(organization_id, generated_at_utc DESC)` WHERE `status='sealed'` | Partial B-tree | Sealed package list for audit trail |

### Indexes Dropped (redundant)

| Index | Table | Reason |
|-------|-------|--------|
| `idx_plan_declarations_contract_fk` | `plan_declarations` | Replaced by composite `idx_plan_declarations_contract_version` (strict superset) |

### EXPLAIN ANALYZE Results

> Populate after running the validation queries in the migration file.

| Query | Pre-Index Plan | Post-Index Plan | Improvement |
|-------|---------------|-----------------|-------------|
| Ledger v1: contract + type + time | Seq Scan | Index Scan | — |
| Ledger v2: OCC timeline | Index Scan | Index Only Scan | — |
| Contracts: active window | Seq Scan | Index Scan (partial) | — |
| Plan declarations: active version | Index Scan | Index Only Scan | — |

---

## 4. Architectural Decision: `evaluation_context_cache`

### Context

The `senior_engineer` council member proposed a denormalized read-model table:

```sql
-- Hypothetical — not yet implemented
CREATE TABLE evaluation_context_cache (
  organization_id UUID NOT NULL,
  contract_id     UUID NOT NULL,
  cached_at_utc   TIMESTAMPTZ NOT NULL,
  context         JSONB NOT NULL,  -- pre-joined: contract + plan + SLA template + zones
  PRIMARY KEY (organization_id, contract_id)
);
```

**Benefit:** Replaces 4–5 JOINs in the EvaluationEngine evaluation path with a single key lookup.

**Cost:** Cache invalidation complexity (must be invalidated when contract, plan, or SLA template changes). Risk of stale context leading to incorrect verdicts (INV-5: Single Decision Engine).

### Ruling

**DEFERRED (Challenger wins for now).**

Reasoning:
1. The composite indexes added in this phase should reduce JOIN latency to < 20ms for typical datasets at MVP scale (< 10,000 contracts per org).
2. The `evaluation_context_cache` introduces a stale-data risk that violates the spirit of INV-5 (Single Decision Engine must evaluate against authoritative data).
3. Revisit if EXPLAIN ANALYZE on steady state load shows p95 JOIN latency > 50ms after indexes are applied.

**Trigger for re-evaluation:** Ledger SELECT p95 > 200ms after Phase 8.6 indexes are applied and steady state is re-run.

---

## 5. Connection Pool Analysis

### Supabase Free Tier Limit: 60 Connections

**Steady State Math:**
```
1,000 VUs × (avg_request_ms / 60,000ms per VU cycle) = peak concurrent requests
At avg INSERT = 150ms:
  1,000 × (150 / 60,000) = 2.5 concurrent DB connections
  Peak burst: ~25 connections (10× jitter factor)
```

**Bulk Flood Math:**
```
200 requests / 2,000ms = 100 req/sec
At avg INSERT = 50ms (simple insert):
  100 × 0.05 = 5 concurrent connections
```

**Combined worst case (steady state + OCC reads + bulk flood):**
```
~25 (steady) + ~10 (OCC reads) + ~5 (flood) = ~40 connections
Buffer to limit: 60 - 40 = 20 connections (safe)
```

**Action threshold:** If Supabase Dashboard shows > 45 connections during load test, add PgBouncer connection pooling (Supabase Pro) or reduce VU count.

---

## 6. Bottlenecks Identified

> Populate after running load tests.

| Bottleneck | Severity | Mitigation |
|------------|----------|-----------|
| (to be filled) | — | — |

---

## 7. Phase 8.6 Definition of Done

- [ ] `k6 run scripts/load_test/k6_basic.js` executed — results pasted in Section 2
- [ ] `k6 run scripts/load_test/k6_chaos_gps.js` executed — results pasted in Section 2.4
- [ ] `EXPLAIN ANALYZE` run on all 6 new indexes — Section 3 table populated
- [ ] Phantom penalty verification SQL shows 0 rows
- [ ] Connection peak verified < 50 during combined load
- [ ] Decision on `evaluation_context_cache` documented (Section 4)
- [ ] Migration `20260403000004_performance_indexes.sql` applied via CI/CD (git push)

---

## 8. Phase 8.7 — Multi-Tenant Isolation Stress Test

**Status:** Script ready — awaiting execution
**Script:** `scripts/load_test/k6_multi_tenant_isolation.js`
**Invariants:** INV-6 (MULTI-TENANT + RLS), INV-10 (RLS TENANT CLAIM)

### 8.1 Test Design

**Method for RLS overhead measurement (Challenger ruling):**
`SET row_security = off` requires superuser — unavailable via Supabase REST API.
Instead: measure latency delta between same-org query (RLS matches, returns data) and
cross-org probe (RLS filters to `[]` — maximum policy evaluation cost with zero rows returned).
Delta = RLS predicate overhead proxy. Target: < 5ms.

**Scenarios:**

| Scenario | VUs | Duration | What it tests |
|----------|-----|----------|---------------|
| `baseline_read` | 50 | 3 min | Org A reads own ledger — establishes SELECT p95 baseline |
| `cross_tenant_probe` | 10 | 3 min | Org B JWT probes Org A data — must get `[]` every time |
| `mixed_org_write` | 500 | 2 min | 250 Org A + 250 Org B concurrent writes — isolation under stress |
| `isolation_verify` | 2 | ~60s | Each org reads back own data, confirms no foreign-org rows present |

**Abort-on-fail thresholds (hard gates):**
- `cross_tenant_leak_count == 0` — any leak aborts the test immediately
- `cross_tenant_returns_empty rate == 1` — 100% of probes must return `[]`

### 8.2 Results

> **Populate this section after running:**
> ```bash
> export SUPABASE_URL="https://<project>.supabase.co"
> export ORG_A_JWT="<jwt-with-app_metadata.org_id=ORG_A>"
> export ORG_B_JWT="<jwt-with-app_metadata.org_id=ORG_B>"
> export ORG_A_ID="<org-a-uuid>"
> export ORG_B_ID="<org-b-uuid>"
> export CONTRACT_A_ID="<contract-uuid-org-a>"
> export CONTRACT_B_ID="<contract-uuid-org-b>"
> k6 run scripts/load_test/k6_multi_tenant_isolation.js
> ```

| Metric | Result | Target | Pass? |
|--------|--------|--------|-------|
| Cross-tenant leak count | — | 0 (hard stop) | — |
| Cross-tenant queries returning `[]` | —% | 100% | — |
| RLS overhead delta (cross p95 − baseline p95) | — ms | < 5ms | — |
| Baseline SELECT p95 (same-org) | — ms | < 500ms | — |
| Cross-tenant SELECT p95 | — ms | < 505ms | — |
| Mixed-org write p95 | — ms | < 200ms | — |

### 8.3 Post-Run Verification SQL

Run in Supabase SQL Editor after the test to confirm no physical data leakage:

```sql
-- A. Rows written as "Org A" must never appear under another org_id
SELECT COUNT(*) AS leak_count
FROM sla_audit_ledger_v2
WHERE set_id LIKE 'mixed-write-A-%'
  AND organization_id != '<ORG_A_ID>';
-- Expected: 0

-- B. Rows written as "Org B" must never appear under another org_id
SELECT COUNT(*) AS leak_count
FROM sla_audit_ledger_v2
WHERE set_id LIKE 'mixed-write-B-%'
  AND organization_id != '<ORG_B_ID>';
-- Expected: 0

-- C. RLS overhead via EXPLAIN ANALYZE (run outside load test)
EXPLAIN ANALYZE
SELECT id FROM sla_audit_ledger_v2
WHERE organization_id = '<ORG_A_ID>'
ORDER BY occurred_at_utc DESC LIMIT 50;
-- Look for: Index Scan using idx_sla_ledger_v2_org_entity_time
-- Actual time should be < 5ms on a non-empty table
```

### 8.4 Phase 8.7 Definition of Done

- [ ] `k6 run scripts/load_test/k6_multi_tenant_isolation.js` executed — results pasted in Section 8.2
- [ ] `cross_tenant_leak_count == 0` confirmed
- [ ] RLS overhead delta < 5ms confirmed
- [ ] Post-run verification SQL (Section 8.3) shows 0 rows for A and B
- [ ] Results saved to `docs/governance/k6_isolation_results.json`

---

## 9. Next Phase

**Phase 8.8 (not yet authorized):** Shadow Mode stress test — run historical data through EvaluationEngine for ROI simulation under tenant load.
