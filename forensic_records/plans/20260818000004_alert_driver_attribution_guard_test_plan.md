# Test Plan: 20260818000004 — Alert Driver Attribution Guard

**Migration:** `supabase/migrations/20260818000004_alert_driver_attribution_guard.sql`
**INV:** INV-18 (Zero-Trust telemetry), INV-DB (zero-downtime)
**Date:** 2026-08-18

## Objective

Verify `chk_alert_driver_attribution` CHECK constraint correctly blocks unattributed alerts for driver-bound types while allowing TELEGRAM_ORPHAN and properly attributed rows.

## Test Cases

| # | Scenario | Expected |
|---|----------|----------|
| T1 | INSERT driver-bound alert with valid `driver_id` in context | `INSERT` succeeds |
| T2 | INSERT driver-bound alert with `driver_id = ''` (empty string) | `23514` check violation |
| T3 | INSERT driver-bound alert with `driver_id = null` JSON value | `23514` check violation |
| T4 | INSERT driver-bound alert with `context` missing `driver_id` key entirely | `23514` check violation |
| T5 | INSERT `TELEGRAM_ORPHAN` alert with no `driver_id` in context | `INSERT` succeeds (exempt) |
| T6 | INSERT `TELEGRAM_ORPHAN` alert with `driver_id` present | `INSERT` succeeds |
| T7 | Existing rows with missing `driver_id` remain unaffected (NOT VALID) | No scan error on migration apply |
| T8 | All driver-bound types (NO_SHOW, EVIDENCE_GAP, PENALTY_APPLIED, DEVIATION, SLA_BREACH, POTENTIAL_TIME_FRAUD) blocked without `driver_id` | `23514` for each |

## Driver-Bound Types to Test (T8)

- `NO_SHOW`
- `EVIDENCE_GAP`
- `PENALTY_APPLIED`
- `DEVIATION`
- `SLA_BREACH`
- `POTENTIAL_TIME_FRAUD`

## Verification Query

```sql
SELECT conname, convalidated
FROM pg_constraint
WHERE conrelid = 'public.operational_alerts'::regclass
  AND conname = 'chk_alert_driver_attribution';
-- convalidated = false confirms NOT VALID (no scan on history)
```

## Rollback

```sql
ALTER TABLE public.operational_alerts
  DROP CONSTRAINT IF EXISTS chk_alert_driver_attribution;
```
