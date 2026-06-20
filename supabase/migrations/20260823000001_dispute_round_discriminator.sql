-- =============================================================================
-- Migration: dispute_round discriminator — recycle the per-entry resolution slot
-- Purpose:   The defense-in-depth unique index uq_ledger_resolution_pN keyed
--            (organization_id, payload->>'queue_entry_id') over
--            type IN ('DISPUTE_ACCEPTED','DISPUTE_OVERTURNED','DISPUTE_RETRACTED')
--            permits exactly ONE resolution fact per queue entry — FOREVER.
--            DISPUTE_RETRACTED is NON-terminal (returns the sanction to 'pending',
--            re-disputable), yet it consumes that single slot. The legitimate flow
--              Solicitar Defesa → Cancelar Solicitação (RETRACTED) →
--              Solicitar Defesa again → Confirmar/Anular (OVERTURNED/ACCEPTED)
--            then collides with the retained RETRACTED row → 23505
--            (duplicate key value violates unique constraint "uq_ledger_resolution_pN").
--
--            Fix: discriminate the uniqueness scope by dispute CYCLE. Each
--            open→resolve round is independent (re-disputes never collide), while
--            same-cycle double-sealing is still blocked (defense-in-depth intact).
--
-- Strategy:  (1) ADD COLUMN sanction_review_queue.dispute_round INT NOT NULL
--                DEFAULT 0 — metadata-only (PG11+ constant default), non-blocking.
--            (2) Swap the per-partition partial unique indexes to key on
--                (organization_id, queue_entry_id, dispute_round). New names avoid
--                the IF NOT EXISTS no-op. DROP INDEX is not in the destructive DDL
--                blocklist (DROP TABLE/COLUMN/DELETE/TRUNCATE) — INV-DB safe.
--
-- Immutability: prevent_srq_immutable_mutation() is a BLOCKLIST (org_id,
--   ledger_entry_id, set_id, contract_id, verdict_evidence, created_at,
--   vehicle_plate, operator_name). dispute_round is NOT listed → freely mutable
--   by dispute_sanction. No trigger change required.
--
-- pr_scanner: ignore-regression — additive column + additive index swap
--   (no merged migration modified; new resolution discriminator). Council-approved
--   (Architect · Senior · QA-Security): preserves INV-3 append-only semantics,
--   strengthens INV-26 (no new oracle), zero-downtime per INV-DB.
--
-- Invariants: INV-3 (ledger append-only), INV-1/INV-22 (org isolation),
--             INV-DB (zero-downtime), INV-6 (UTC unaffected).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Dispute-cycle counter on the queue entry ──────────────────────────────
-- Constant DEFAULT 0 ⇒ metadata-only add (no table rewrite, no full scan).
-- INV-DB: zero-downtime-verified (ADD COLUMN ... NOT NULL DEFAULT <const>).
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS dispute_round INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.sanction_review_queue.dispute_round IS
  'Monotonic dispute-cycle counter. Incremented by dispute_sanction on each open. '
  'Discriminates the resolution-fact unique index so a re-dispute (after retract) '
  'never collides with a prior cycle while same-cycle double-seal stays blocked.';

-- ── 2. Swap the resolution-fact unique indexes onto the cycle discriminator ──
-- FOR UPDATE on the queue row is the PRIMARY race guard; these partial unique
-- indexes are the secondary backstop against a direct duplicate INSERT that
-- bypasses the RPC. The ledger is HASH-partitioned by organization_id and the key
-- leads with organization_id, so (org_id, queue_entry_id, dispute_round) always
-- routes to one partition — per-partition uniqueness is globally sufficient.
-- Partial UNIQUE is unsupported on the partitioned PARENT → declared per child.
--
-- Historical resolution rows carry no 'dispute_round' in payload → ->> yields
-- NULL; NULLs are distinct in a unique index, so existing rows never collide on
-- the rebuild. New rows always embed a non-null dispute_round (≥ 0).
DROP INDEX IF EXISTS public.uq_ledger_resolution_p0;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p1;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p2;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p3;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p0
  ON public.sla_audit_ledger_p0
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p1
  ON public.sla_audit_ledger_p1
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p2
  ON public.sla_audit_ledger_p2
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p3
  ON public.sla_audit_ledger_p3
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');

RESET client_min_messages;
