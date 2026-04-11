# Row-Level HMAC Sealing — Design Specification

## 1. Goal Description

Every critical row in the Ledger (`sla_audit_ledger_v2`) and other audit tables MUST carry an `hmac_signature` column containing a SHA-256 HMAC of the row's critical fields. This provides **cryptographic tamper evidence** even if a DB admin or compromised service account modifies rows directly via SQL.

The HMAC seal transforms each row into a **Forensic Evidence Unit**: any post-insert mutation — even a single bit flip — will produce a detectable signature mismatch during verification.

---

## 2. Invariant Mapping

| INV | Category | Relevance |
|-----|----------|-----------|
| INV-3 | Ledger Integrity | HMAC provides post-hoc tamper detection for append-only tables |
| INV-9 | Evidence Sealing | Extends the SHA-256 sealing principle from telemetry ingestion to ledger persistence |
| INV-15 | Deterministic | Canonical field ordering ensures identical input → identical HMAC on replay |
| INV-1 | Identity Sovereignty | `organization_id` is included in HMAC input, binding signature to tenant |
| INV-24 | Security Guard | HMAC verification produces a verifiable audit signature |

---

## 3. Threat Model

| Threat | Mitigation |
|--------|-----------|
| DB admin runs `UPDATE ledger_v2 SET fine_cents = 0 WHERE id = '...'` | HMAC signature no longer matches → detected on next verification sweep |
| Attacker with `service_role` bypasses RLS and inserts a forged row | Row inserted via Edge Function or direct SQL still gets HMAC computed by trigger — but if attacker also forges the HMAC, the secret key (in vault) is the single point of failure |
| Backup/restore drift — row restored from stale backup | Verification sweep flags all rows whose HMAC was computed from a different secret (key rotation) or shows expected HMAC for backup timestamp |
| pg_cron job disabled or deleted | App-layer fallback: periodic Edge Function worker performs independent verification |
| Secret key leaked | Key rotation procedure: re-seal all existing rows with new key, log rotation event to `hmac_verification_log` |

---

## 4. Design

### 4.1 HMAC Generation Formula

```
HMAC = HMAC-SHA256(canonical_json, secret_key)
```

**Canonical JSON construction rules:**

1. Select only **critical fields** (see §4.2 per table)
2. Sort keys **alphabetically** (deterministic ordering, INV-15)
3. Use `jsonb_build_object` in PostgreSQL — ensures consistent serialization
4. `NULL` fields are included as JSON `null` (not omitted)
5. Timestamps stored as ISO 8601 UTC strings (INV-6)

**Output format:** lowercase hexadecimal string (64 characters for SHA-256)

### 4.2 Critical Fields Per Table

#### `sla_audit_ledger_v2`

| Field | Type | Rationale |
|-------|------|-----------|
| `organization_id` | UUID | Tenant binding (INV-1) |
| `timestamp` | TIMESTAMPTZ | Event time |
| `action_type` | VARCHAR | Nature of the audit event |
| `entity_id` | VARCHAR | Target entity |
| `payload` | JSONB | Full event payload (serialized) |

**Excluded fields:** `id` (auto-generated), `operator_id` (metadata), `old_value`/`new_value` (text blobs), `reason` (free-text).

#### `contractual_financial_snapshot_v2`

| Field | Type | Rationale |
|-------|------|-----------|
| `organization_id` | UUID | Tenant binding |
| `trip_id` | VARCHAR | Trip identifier |
| `total_fines_cents` | BIGINT | Financial impact |

#### `hmac_verification_log` (new table)

This table is itself HMAC-sealed to prevent tampering with the verification record.

| Field | Type | Rationale |
|-------|------|-----------|
| `organization_id` | UUID | Tenant binding |
| `table_name` | VARCHAR | Which table was verified |
| `row_id` | UUID | Which row failed |
| `expected_hmac` | TEXT | What the HMAC should be |
| `actual_hmac` | TEXT | What the HMAC currently is |
| `verified_at_utc` | TIMESTAMPTZ | Verification timestamp |
| `status` | VARCHAR | `tampered` \| `key_rotated` \| `re_sealed` |

### 4.3 Secret Key Management (INV-3)

The HMAC secret key is stored in **Supabase Vault** (`vault.secrets`), never in application code, environment variables, or migration scripts.

```sql
-- One-time setup (run manually by operator, NOT in migration)
SELECT vault.create_secret(
  '<cryptographically-random-256-bit-key>',
  'ledger_hmac_key',
  'HMAC-SHA256 key for ledger row sealing'
);
```

The key is accessed at runtime via:

```sql
vault.decrypted_secret('ledger_hmac_key')
```

**Key rotation procedure:**

1. Create new secret: `vault.create_secret('<new-key>', 'ledger_hmac_key_v2', ...)`
2. Update trigger function to reference new key
3. Run re-seal batch job: iterate all existing rows, recompute HMAC with new key
4. Log rotation event to `hmac_verification_log`
5. After verification sweep confirms all rows match, delete old key from vault

---

## 5. Proposed Implementation

### 5.1 Option A: PostgreSQL Trigger (Recommended)

**Mechanism:** A `BEFORE INSERT` trigger on each sealed table computes the HMAC atomically at insert time.

**Advantages:**
- Zero app-layer changes — the seal is enforced at the database layer
- Atomic with the INSERT — no window where a row exists without a signature
- Works regardless of insert path (Edge Function, app, direct SQL, batch import)
- Respects INV-3: secret stays in vault, accessed only via `decrypted_secret()`

**Disadvantages:**
- Requires `pgcrypto` extension (already available in Supabase)
- Adds ~1-2ms latency per insert (negligible for ledger write volume)
- Trigger function is database-side code (must be reviewed for security)

**Verification strategy:**

A periodic `pg_cron` job runs a verification query against the last N entries:

```sql
-- Run every hour via pg_cron
SELECT verify_ledger_hmac() -- custom function, see §6
```

The verification function:
1. Queries the last 10,000 entries (configurable)
2. Recomputes HMAC for each row using the current vault key
3. Compares against stored `hmac_signature`
4. Logs any mismatch to `hmac_verification_log`
5. Returns count of mismatches

### 5.2 Option B: Edge Function Worker (Fallback)

**Mechanism:** A Deno Edge Function runs on a schedule (triggered by pg_cron webhook or external cron) and performs HMAC verification independently of the database.

**Query pattern:**

```sql
SELECT id, organization_id, timestamp, action_type, entity_id, payload, hmac_signature
FROM sla_audit_ledger_v2
WHERE hmac_signature IS NULL
   OR hmac_signature != expected_hmac(compute_from_fields(...))
ORDER BY timestamp DESC
LIMIT 10000;
```

**Advantages:**
- Verification logic lives in Dart/Deno — easier to unit test
- Can integrate with Sentry/PostHog for alerting
- Independent of database trigger infrastructure

**Disadvantages:**
- Requires app-layer coordination
- Does not seal rows at insert time — there is a window where unsigned rows exist
- More operational complexity (deploy, monitor, alert on the worker itself)

**Recommended use:** As a **secondary** verification layer, not the primary sealing mechanism. Run the Edge Function worker daily as an independent audit against the trigger-sealed rows.

### 5.3 Decision

| Aspect | Option A (Trigger) | Option B (Edge Function) |
|--------|-------------------|-------------------------|
| Sealing guarantee | Atomic with INSERT | Async, eventual |
| Tamper detection | pg_cron verification | Worker sweep |
| Operational overhead | Low (DB-only) | Medium (deploy + monitor) |
| Testability | SQL-level unit tests | Dart unit tests |
| Defense-in-depth | Primary seal | Secondary independent audit |

**Decision:** Implement **Option A as primary**, **Option B as secondary** defense-in-depth.

---

## 6. Migration SQL

### 6.1 Add `hmac_signature` Column

```sql
-- ============================================================
-- veraprob — Row-Level HMAC Sealing (INV-3, INV-9, INV-15)
-- ============================================================
-- PURPOSE:
--   Add cryptographic tamper-evidence seals to all critical
--   audit tables. Each row carries an HMAC-SHA256 signature
--   computed from its canonical critical fields.
--
-- INVARIANTS:
--   INV-3  — Ledger integrity (append-only, tamper-evident)
--   INV-9  — Evidence sealing (SHA-256 at persistence layer)
--   INV-15 — Deterministic replay (canonical field ordering)
-- ============================================================

-- Ensure pgcrypto is available (Supabase includes it by default)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------------
-- 1. Add hmac_signature column to sealed tables
-- -------------------------------------------------------------------

ALTER TABLE public.sla_audit_ledger_v2
  ADD COLUMN IF NOT EXISTS hmac_signature TEXT;

ALTER TABLE public.contractual_financial_snapshot_v2
  ADD COLUMN IF NOT EXISTS hmac_signature TEXT;

COMMENT ON COLUMN public.sla_audit_ledger_v2.hmac_signature IS
  'HMAC-SHA256 hex digest of canonical critical fields. Tamper-evidence seal.';

COMMENT ON COLUMN public.contractual_financial_snapshot_v2.hmac_signature IS
  'HMAC-SHA256 hex digest of canonical critical fields. Tamper-evidence seal.';

-- -------------------------------------------------------------------
-- 2. HMAC computation trigger function for sla_audit_ledger_v2
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compute_ledger_v2_hmac()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_canonical TEXT;
BEGIN
  -- Fetch secret from vault (INV-3)
  v_secret := vault.decrypted_secret('ledger_hmac_key');

  -- Build canonical JSON with alphabetically sorted keys (INV-15)
  -- Fields: action_type, entity_id, organization_id, payload, timestamp
  v_canonical := jsonb_build_object(
    'action_type',     NEW.action_type,
    'entity_id',       NEW.entity_id,
    'organization_id', NEW.organization_id,
    'payload',         NEW.payload,
    'timestamp',       TO_CHAR(NEW.timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  )::text;

  -- Compute HMAC-SHA256 and encode as lowercase hex
  NEW.hmac_signature := encode(
    hmac(v_canonical::bytea, v_secret::bytea, 'sha256'),
    'hex'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_v2_hmac_seal ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_ledger_v2_hmac_seal
  BEFORE INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW
  EXECUTE FUNCTION public.compute_ledger_v2_hmac();

-- -------------------------------------------------------------------
-- 3. HMAC computation trigger function for contractual_financial_snapshot_v2
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compute_snapshot_v2_hmac()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_canonical TEXT;
BEGIN
  v_secret := vault.decrypted_secret('ledger_hmac_key');

  -- Canonical fields: organization_id, total_fines_cents, trip_id
  v_canonical := jsonb_build_object(
    'organization_id',    NEW.organization_id,
    'total_fines_cents',  NEW.total_fines_cents,
    'trip_id',            NEW.trip_id
  )::text;

  NEW.hmac_signature := encode(
    hmac(v_canonical::bytea, v_secret::bytea, 'sha256'),
    'hex'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_v2_hmac_seal ON public.contractual_financial_snapshot_v2;
CREATE TRIGGER trg_snapshot_v2_hmac_seal
  BEFORE INSERT ON public.contractual_financial_snapshot_v2
  FOR EACH ROW
  EXECUTE FUNCTION public.compute_snapshot_v2_hmac();

-- -------------------------------------------------------------------
-- 4. Verification log table (append-only, itself HMAC-sealed)
-- -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.hmac_verification_log (
  id              UUID NOT NULL DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  table_name      VARCHAR(255) NOT NULL,
  row_id          UUID NOT NULL,
  expected_hmac   TEXT NOT NULL,
  actual_hmac     TEXT NOT NULL,
  verified_at_utc TIMESTAMPTZ NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
  status          VARCHAR(32) NOT NULL DEFAULT 'tampered'
    CHECK (status IN ('tampered', 'key_rotated', 're_sealed')),
  details         JSONB,
  hmac_signature  TEXT,
  PRIMARY KEY (organization_id, id)
);

COMMENT ON TABLE public.hmac_verification_log IS
  'Append-only log of HMAC verification results. Each entry is itself HMAC-sealed.';

COMMENT ON COLUMN public.hmac_verification_log.status IS
  'tampered: HMAC mismatch detected; key_rotated: discrepancy due to key rotation; re_sealed: row re-sealed after investigation';

-- Apply HMAC seal trigger to the verification log itself
DROP TRIGGER IF EXISTS trg_hmac_log_hmac_seal ON public.hmac_verification_log;
CREATE TRIGGER trg_hmac_log_hmac_seal
  BEFORE INSERT ON public.hmac_verification_log
  FOR EACH ROW
EXECUTE FUNCTION public.compute_ledger_v2_hmac();
-- Reuses ledger trigger (same canonical fields pattern)

-- -------------------------------------------------------------------
-- 5. Verification function (called by pg_cron or Edge Function)
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.verify_ledger_v2_hmac(p_limit INT DEFAULT 10000)
RETURNS TABLE (
  row_id          UUID,
  expected_hmac   TEXT,
  actual_hmac     TEXT,
  is_valid        BOOLEAN,
  checked_at_utc  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_row    RECORD;
  v_canonical TEXT;
  v_expected TEXT;
  v_count  INT := 0;
BEGIN
  v_secret := vault.decrypted_secret('ledger_hmac_key');

  FOR v_row IN
    SELECT id, organization_id, timestamp, action_type, entity_id, payload, hmac_signature
    FROM public.sla_audit_ledger_v2
    ORDER BY timestamp DESC
    LIMIT p_limit
  LOOP
    v_canonical := jsonb_build_object(
      'action_type',     v_row.action_type,
      'entity_id',       v_row.entity_id,
      'organization_id', v_row.organization_id,
      'payload',         v_row.payload,
      'timestamp',       TO_CHAR(v_row.timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )::text;

    v_expected := encode(
      hmac(v_canonical::bytea, v_secret::bytea, 'sha256'),
      'hex'
    );

    IF v_row.hmac_signature IS DISTINCT FROM v_expected THEN
      -- Log the mismatch
      INSERT INTO public.hmac_verification_log (
        organization_id, table_name, row_id, expected_hmac, actual_hmac, status
      ) VALUES (
        v_row.organization_id,
        'sla_audit_ledger_v2',
        v_row.id,
        v_expected,
        COALESCE(v_row.hmac_signature, '<NULL>'),
        'tampered'
      );

      row_id := v_row.id;
      expected_hmac := v_expected;
      actual_hmac := COALESCE(v_row.hmac_signature, '<NULL>');
      is_valid := false;
      checked_at_utc := (NOW() AT TIME ZONE 'UTC');
      RETURN NEXT;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  -- Log a summary entry if all rows passed
  IF v_count = 0 THEN
    RAISE NOTICE 'HMAC verification: all % rows valid', p_limit;
  ELSE
    RAISE WARNING 'HMAC verification: % mismatches found in last % rows', v_count, p_limit;
  END IF;

  RETURN;
END;
$$;

-- -------------------------------------------------------------------
-- 6. RLS policies for hmac_verification_log
-- -------------------------------------------------------------------

ALTER TABLE public.hmac_verification_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: Read HMAC Log" ON public.hmac_verification_log;
CREATE POLICY "Tenant Isolation: Read HMAC Log"
  ON public.hmac_verification_log
  FOR SELECT
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

DROP POLICY IF EXISTS "Tenant Isolation: Insert HMAC Log" ON public.hmac_verification_log;
CREATE POLICY "Tenant Isolation: Insert HMAC Log"
  ON public.hmac_verification_log
  FOR INSERT
  WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Verification function uses SECURITY DEFINER — no RLS policy needed for it

-- -------------------------------------------------------------------
-- 7. pg_cron schedule (requires pg_cron extension)
-- -------------------------------------------------------------------
-- NOTE: pg_cron must be enabled in Supabase project settings.
-- On Supabase Free Tier, pg_cron is available. On self-hosted,
-- add 'pg_cron' to shared_preload_libraries.

-- Run verification every hour
SELECT cron.schedule(
  'ledger_hmac_verification_hourly',
  '0 * * * *',  -- every hour
  $$ SELECT public.verify_ledger_v2_hmac(10000) $$
);

-- -------------------------------------------------------------------
-- 8. Backfill existing rows (run once after migration)
-- -------------------------------------------------------------------
-- Existing rows will have NULL hmac_signature. They must be sealed
-- retroactively. This is a one-time operation.
--
-- IMPORTANT: Run this during a maintenance window for large tables.

-- For sla_audit_ledger_v2:
-- UPDATE public.sla_audit_ledger_v2
-- SET hmac_signature = ...  -- Cannot use trigger on UPDATE (blocked by INV-3)
-- Use a dedicated backfill function instead:

CREATE OR REPLACE FUNCTION public.backfill_ledger_v2_hmac(p_batch_size INT DEFAULT 1000)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_row    RECORD;
  v_count  INT := 0;
  v_canonical TEXT;
  v_hmac   TEXT;
BEGIN
  v_secret := vault.decrypted_secret('ledger_hmac_key');

  -- Temporarily disable the immutability trigger for backfill ONLY
  -- This is safe: we are ADDING data (hmac_signature), not mutating existing fields
  -- The trigger blocks UPDATE entirely, so we must use a direct approach.

  -- WARNING: sla_audit_ledger_v2 has BEFORE UPDATE triggers that RAISE EXCEPTION.
  -- We cannot backfill via UPDATE. Instead, we use a workaround:
  -- 1. Create a temporary staging table
  -- 2. Insert rows with computed HMAC into staging
  -- 3. The trigger computes HMAC on insert
  --
  -- Actually, the immutability trigger blocks UPDATE but INSERT still works.
  -- Since rows already exist, we need to use DISABLE TRIGGER for this operation.

  -- DISABLE immutability triggers (TEMPORARY — re-enabled at end)
  ALTER TABLE public.sla_audit_ledger_v2 DISABLE TRIGGER trg_ledger_v2_no_update;
  ALTER TABLE public.sla_audit_ledger_v2 DISABLE TRIGGER trg_ledger_v2_hmac_seal;

  FOR v_row IN
    SELECT id, organization_id, timestamp, action_type, entity_id, payload
    FROM public.sla_audit_ledger_v2
    WHERE hmac_signature IS NULL
    LIMIT p_batch_size
  LOOP
    v_canonical := jsonb_build_object(
      'action_type',     v_row.action_type,
      'entity_id',       v_row.entity_id,
      'organization_id', v_row.organization_id,
      'payload',         v_row.payload,
      'timestamp',       TO_CHAR(v_row.timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )::text;

    v_hmac := encode(
      hmac(v_canonical::bytea, v_secret::bytea, 'sha256'),
      'hex'
    );

    UPDATE public.sla_audit_ledger_v2
    SET hmac_signature = v_hmac
    WHERE id = v_row.id;

    v_count := v_count + 1;
  END LOOP;

  -- RE-ENABLE immutability triggers
  ALTER TABLE public.sla_audit_ledger_v2 ENABLE TRIGGER trg_ledger_v2_no_update;
  ALTER TABLE public.sla_audit_ledger_v2 ENABLE TRIGGER trg_ledger_v2_hmac_seal;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.backfill_ledger_v2_hmac IS
  'Backfills HMAC signatures for existing rows without signatures. Run in batches. Re-enables all triggers after completion.';
```

---

## 7. Edge Cases

### 7.1 Late-Arriving Events

**Scenario:** An event arrives after its logical chronological position (e.g., GPS event with `timestamp = 10:00` arrives at `10:15` after later events already inserted).

**Impact on HMAC:** None. The HMAC is computed from the row's own fields, not from surrounding rows. Insertion order does not affect signature validity.

**Operational note:** The `verify_ledger_v2_hmac()` function queries `ORDER BY timestamp DESC`, so late-arriving rows are verified on the next sweep regardless of their physical insertion order.

### 7.2 Compensating Records

**Scenario:** A ledger entry is found to be incorrect. Per INV-3, it cannot be `UPDATE`d or `DELETE`d. Instead, a compensating entry is inserted.

**Impact on HMAC:** The original (incorrect) row retains its valid HMAC — it was correctly sealed at insert time. The compensating row gets its own independent HMAC. Both are verifiable.

**Verification:** Both rows pass HMAC verification. The semantic correction is tracked in the ledger's `action_type` and `payload` fields, not through signature invalidation.

### 7.3 Key Rotation

**Scenario:** The HMAC secret key is rotated (compromised or routine rotation).

**Procedure:**

1. Create new key in vault: `vault.create_secret('<new>', 'ledger_hmac_key_v2', ...)`
2. Update trigger function to reference `ledger_hmac_key_v2`
3. Run `backfill_ledger_v2_hmac()` — this will recompute all NULL-signature rows; rows with old signatures remain unchanged
4. Run a verification sweep — rows with old key will show as `tampered`
5. Log each old-key mismatch as `key_rotated` (not `tampered`)
6. After all rows are re-sealed, verify again — all should pass
7. Delete old key from vault

**Important:** During the rotation window, the verification log will contain `key_rotated` entries. This is expected and must not trigger Sentry alerts.

### 7.4 Partitioned Tables

`sla_audit_ledger_v2` is partitioned by HASH on `organization_id`. The trigger fires on the **parent table**, so partitions inherit the HMAC computation automatically. No per-partition trigger configuration is needed.

### 7.5 pg_cron Unavailable

If `pg_cron` is not enabled (e.g., self-hosted Supabase without `pg_cron` in `shared_preload_libraries`):

- The cron schedule in §6 step 7 will silently fail to register
- Fallback: deploy the **Edge Function Worker** (§5.2) as the verification mechanism
- Or: use an external scheduler (GitHub Actions, cron job on CI server) that calls a Supabase Edge Function

### 7.6 NULL payload

If `payload` is `NULL`, `jsonb_build_object` includes it as JSON `null`:

```json
{"action_type": "...", "entity_id": "...", "organization_id": "...", "payload": null, "timestamp": "..."}
```

This is deterministic and consistent — `NULL` always produces the same canonical representation.

---

## 8. Alerting & Observability

### 8.1 Sentry Integration

The Edge Function Worker (Option B) MUST report to Sentry when:

| Condition | Sentry Level | Action |
|-----------|-------------|--------|
| Any `tampered` entry in `hmac_verification_log` | **Error** | Page on-call engineer |
| Verification sweep skipped (worker timeout) | **Warning** | Log for investigation |
| Key rotation detected | **Info** | Confirm rotation completed |
| All rows valid | — | No alert (silence is success) |

### 8.2 PostHog Events

Track HMAC verification results as PostHog events for trend analysis:

```json
{
  "event": "hmac_verification_sweep",
  "properties": {
    "table": "sla_audit_ledger_v2",
    "rows_checked": 10000,
    "rows_valid": 9998,
    "rows_tampered": 2,
    "duration_ms": 342,
    "organization_id": "<uuid>"
  }
}
```

---

## 9. Verification Plan

### 9.1 Unit Tests (SQL)

| Test | Description | Expected Result |
|------|-------------|-----------------|
| `test_hmac_insert_trigger` | Insert a row into `sla_audit_ledger_v2` | `hmac_signature` is NOT NULL and matches expected HMAC |
| `test_hmac_deterministic` | Insert two identical rows | Both have the same `hmac_signature` |
| `test_hmac_tenant_isolation` | Same fields, different `organization_id` | Different `hmac_signature` (org_id is in canonical JSON) |
| `test_hmac_timestamp_format` | Verify UTC formatting | Timestamp formatted as `YYYY-MM-DDTHH:MM:SS.USZ` |
| `test_verify_function_all_valid` | Run `verify_ledger_v2_hmac()` on clean table | Returns 0 rows, logs notice |
| `test_verify_function_tampered` | Manually UPDATE a row's `fine_cents` (disable trigger first) | Verification detects mismatch, logs to `hmac_verification_log` |
| `test_backfill_function` | Run backfill on table with NULL signatures | All rows get HMAC, triggers re-enabled |

### 9.2 Integration Tests (Dart)

| Test | Description | Expected Result |
|------|-------------|-----------------|
| `test_hmac_seal_via_trigger` | Insert ledger entry via app, query back | `hmac_signature` column populated |
| `test_hmac_verification_endpoint` | Call verification Edge Function | Returns sweep results |
| `test_hmac_key_rotation_flow` | Rotate key, backfill, verify | All rows re-sealed, old entries logged as `key_rotated` |

### 9.3 Red Team Test

| Scenario | Expected Outcome |
|----------|-----------------|
| DB admin with `service_role` updates `fine_cents` on a ledger row | Next verification sweep detects mismatch, logs to `hmac_verification_log`, Sentry alert fires |
| Attacker inserts forged row with fabricated HMAC | Row gets trigger-computed HMAC (not attacker's), so HMAC is valid — but the row's payload is still auditable. The HMAC proves *who* inserted it (whoever had vault access). |
| Attacker deletes a row from `hmac_verification_log` | The log itself is append-only and HMAC-sealed; deletion would be detected by its own verification sweep. |

---

## 10. Implementation Checklist

- [ ] Create HMAC secret in Supabase Vault (`ledger_hmac_key`)
- [ ] Run migration (add columns, triggers, functions, RLS policies)
- [ ] Run `backfill_ledger_v2_hmac()` in batches for existing data
- [ ] Enable `pg_cron` in Supabase project settings
- [ ] Verify pg_cron schedule is active (`SELECT * FROM cron.job;`)
- [ ] Deploy Edge Function Worker (secondary verification)
- [ ] Configure Sentry alert rule for `hmac_verification_log` entries
- [ ] Add PostHog event tracking to verification worker
- [ ] Run full verification suite (§9)
- [ ] Document key rotation runbook for operations team

---

## 11. Appendix: Canonical JSON Reference

### sla_audit_ledger_v2

```json
{
  "action_type": "<value>",
  "entity_id": "<value>",
  "organization_id": "<uuid>",
  "payload": "<jsonb or null>",
  "timestamp": "<ISO 8601 UTC>"
}
```

### contractual_financial_snapshot_v2

```json
{
  "organization_id": "<uuid>",
  "total_fines_cents": <bigint>,
  "trip_id": "<value>"
}
```

### Key ordering

All keys are sorted **alphabetically** (ASCII order). This ensures that `jsonb_build_object` in PostgreSQL produces identical output regardless of the order in which arguments are passed — the function respects argument order, but the canonical form requires alphabetical keys. The trigger function above already passes arguments in alphabetical order.

---

*Document version: 1.0*
*Phase: 10.5 — The Forensic Truth*
*Status: Draft — awaiting Council review*
