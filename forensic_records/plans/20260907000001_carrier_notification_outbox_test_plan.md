# Test Plan: Carrier Notification Outbox & Unified Trigger

## 1. Description of Changes

This migration implements **Fase 10.7 (P3)**: Carrier notification outbox and transactional unified trigger.

- **`carrier_notification_outbox`**: Append-only table mirroring `webhook_delivery_logs`. Stores carrier email notifications to be dispatched via Resend. Implements INV-1 (org scoped), INV-3 (immutability), INV-4 (bigint cents), and INV-22 (tenant isolation via RLS). Uses `UNIQUE (organization_id, ledger_entry_id, carrier_email)` for idempotency.
- **`enqueue_resolution_events()`**: Renames and replaces `enqueue_verdict_webhooks()`. Now enqueues events to BOTH `webhook_delivery_logs` AND `carrier_notification_outbox` in the same atomic PL/pgSQL transaction to ensure 100% data consistency (no race conditions, no partial failures).
  - **Recipient resolution:** the carrier email is the **autuada carrier's** address, resolved `ledger.contract_id → contracts.id → contracts.contractor_id → contractors.primary_email` (org-scoped, INV-1). It is deliberately NOT `organizations.contact_email` (the embarcador's own mailbox — notifying it would leave the "não fui avisado" defense standing).
  - **Deliverability guard (Zero-Trust):** enqueues only for a deliverable address. NULL/empty and the `@placeholder.invalid` backfill sentinel (20260806000001) are skipped so a guaranteed bounce cannot pollute the outbox with DEAD noise. The sealed verdict itself remains the immutable system of record in the ledger.
- **`drain_pending_carrier_notifications()`**: RPC for the Edge Function to concurrently fetch pending emails (`SKIP LOCKED`). Applies a **2-minute lease** (`next_attempt_at = NOW() + 2 min`) mirroring `drain_pending_webhooks`' DELIVERING lease, so overlapping/slow drains cannot re-pick a row before the dispatcher resolves it — preventing duplicate Resend sends.
- **`carrier_notification_fail()`**: RPC for the Edge Function to record exponential backoff failures (30s→240s), escalating to DEAD after 5 attempts. Org-scoped: a wrong-org call is a silent no-op (anti-oracle INV-26).

## 2. Invariants Addressed

- **INV-1 (Org Isolation)**: Handled by `organization_id` foreign key and checks in RPCs.
- **INV-2 (RLS Path)**: Handled by `auth.jwt() ->> 'organization_id'` in `cno_tenant_select`.
- **INV-3 (Append-Only/Immutability)**: Handled by `trg_cno_immutability` and `trg_cno_no_delete`.
- **INV-4 (BigInt Currency)**: Handled by `fine_cents BIGINT`.
- **INV-6 (UTC Timestamps)**: Handled by `TIMESTAMPTZ`.
- **INV-DB (Zero-Downtime)**: Additive schema only (CREATE TABLE, CREATE FUNCTION). `CREATE OR REPLACE FUNCTION` and `DROP/CREATE TRIGGER` is safe.
- **INV-DATA-API-GRANT (Explicit Grants)**: Handled by `REVOKE ALL FROM PUBLIC, anon; GRANT SELECT TO authenticated; GRANT ALL TO service_role`.
- **INV-22 (Tenant Isolation)**: Handled by RLS.

## 3. Test Cases (pgTAP — `plan(21)`)

Fixture: one tenant, two carriers (Carrier A with a deliverable email, Carrier B with the `@placeholder.invalid` sentinel), each owning a contract; one active webhook endpoint.

- **Structural** (1–2): outbox table exists; unified trigger `trg_enqueue_verdict_webhooks` present.
- **Atomic fan-out on Carrier A's contract** (3–7): `VERDICT_SEALED` inserts 1 `webhook_delivery_logs` row AND 1 `carrier_notification_outbox` row; the outbox `carrier_email` equals **Carrier A's `primary_email`** (proving contract-routed recipient, not tenant email); `fine_cents = 125000`; `verdict_outcome = 'SEALED'`.
- **Deliverability guard on Carrier B's contract** (8–9): `VERDICT_REFUSED` enqueues **0** carrier rows (placeholder email skipped) but still **1** ERP webhook row.
- **Non-terminal skip** (10): `EXECUTION_BOUND` enqueues nothing.
- **Idempotency** (11): re-enqueue of the same `(org, ledger_entry, email)` is a no-op (`ON CONFLICT DO NOTHING`).
- **Append-only** (12–13): mutating a sealed field (`fine_cents`) and `DELETE` both raise (INV-3 guards).
- **Drain lease** (14–15): first `drain_pending_carrier_notifications` reserves the row; an immediate second call returns 0 (2-minute lease → no duplicate dispatch).
- **Failure path** (16–18): `carrier_notification_fail` → `FAILED` with backoff; after max attempts → `DEAD`.
- **Anti-oracle** (19): `carrier_notification_fail` for the wrong org is a silent no-op (row untouched, INV-1/INV-26).
- **RLS isolation** (20–21): `authenticated` with its own `app_metadata.org_id` claim sees its row; a foreign org claim sees 0 (INV-2/INV-22).

## 4. Rollback Plan

```sql
DROP FUNCTION IF EXISTS public.carrier_notification_fail(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.drain_pending_carrier_notifications(UUID, INT);

-- Restore the original trigger function (from 20260905000003_expand_webhook_payload.sql)
CREATE OR REPLACE FUNCTION public.enqueue_verdict_webhooks()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
-- [Original code restored here]
$$;

DROP TRIGGER IF EXISTS trg_enqueue_verdict_webhooks ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_enqueue_verdict_webhooks
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_verdict_webhooks();

DROP FUNCTION IF EXISTS public.enqueue_resolution_events();

DROP TABLE IF EXISTS public.carrier_notification_outbox;
```
