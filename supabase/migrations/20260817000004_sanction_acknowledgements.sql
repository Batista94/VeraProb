-- =============================================================================
-- Migration: sanction_acknowledgements — Sprint A (De Acordo) M4
-- Purpose:   Forensic record of a carrier formally accepting a penalty
--            ("De Acordo"). Triple-signal design (council decision):
--              (1) this table — forensic detail + hash binding,
--              (2) sanction_review_queue.status = 'acknowledged' (TERMINAL) —
--                  the operational AR index,
--              (3) ledger fact SANCTION_ACKNOWLEDGED (INV-3) — emitted by M5 RPC.
--            All three are written atomically by the M5 acknowledge RPCs.
--
--            Hash-bound: a PORTAL_TOKEN acknowledgement can only reference the
--            snapshot_hash the system provably served (DISPUTE_PORTAL_TOKEN_ACCESSED
--            ledger fact) — the carrier cannot "agree" to a value it never saw.
--            INTERNAL_RECORD captures off-band acceptance (email/phone) by a
--            TENANT_ADMIN, with no hash.
--
-- No UNIQUE on queue_entry_id: overturn → re-applied → new acknowledgement cycles
-- are legal; the operational gate is the terminal queue status, not this table.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-22, INV-DATA-API-GRANT.
-- Depends on: 20260406000001 (srq), 20260814000002 (token table).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sanction_acknowledgements (
  id                          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id             UUID        NOT NULL REFERENCES public.organizations(id),
  queue_entry_id              UUID        NOT NULL REFERENCES public.sanction_review_queue(id),

  -- The exact snapshot hash the carrier acknowledged. NULL for INTERNAL_RECORD.
  snapshot_hash_acknowledged  TEXT
    CONSTRAINT chk_sack_hash_format CHECK (
      snapshot_hash_acknowledged IS NULL
      OR snapshot_hash_acknowledged ~ '^[a-f0-9]{64}$'
    ),

  acknowledgement_method      TEXT        NOT NULL
    CONSTRAINT chk_sack_method CHECK (
      acknowledgement_method IN ('PORTAL_TOKEN', 'INTERNAL_RECORD')
    ),
  acknowledged_via_token_id   UUID        REFERENCES public.dispute_portal_tokens(id),
  acknowledged_by_user_id     UUID,
  notes                       TEXT,
  acknowledged_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Each method has exactly one valid shape (defense in depth alongside the RPC).
  CONSTRAINT chk_sack_method_consistency CHECK (
    (acknowledgement_method = 'PORTAL_TOKEN'
       AND snapshot_hash_acknowledged IS NOT NULL
       AND acknowledged_via_token_id  IS NOT NULL)
    OR
    (acknowledgement_method = 'INTERNAL_RECORD'
       AND acknowledged_by_user_id IS NOT NULL)
  )
);

COMMENT ON TABLE public.sanction_acknowledgements IS
  'Forensic record of formal penalty acceptance (De Acordo). Append-only (INV-3). Hash-bound to the served snapshot for PORTAL_TOKEN.';

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sack_org_queue
  ON public.sanction_acknowledgements (organization_id, queue_entry_id);
CREATE INDEX IF NOT EXISTS idx_sack_token
  ON public.sanction_acknowledgements (acknowledged_via_token_id)
  WHERE acknowledged_via_token_id IS NOT NULL;

-- ── Append-only triggers (INV-3) ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_sack_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'sanction_acknowledgements is append-only (INV-3). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS trg_sack_no_update ON public.sanction_acknowledgements;
CREATE TRIGGER trg_sack_no_update
  BEFORE UPDATE ON public.sanction_acknowledgements
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sack_mutation();

CREATE OR REPLACE FUNCTION public.prevent_sack_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'sanction_acknowledgements is append-only (INV-3). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS trg_sack_no_delete ON public.sanction_acknowledgements;
CREATE TRIGGER trg_sack_no_delete
  BEFORE DELETE ON public.sanction_acknowledgements
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sack_delete();

-- ── RLS (INV-2, INV-22): org-scoped SELECT; INSERT via SECURITY DEFINER RPC ──
ALTER TABLE public.sanction_acknowledgements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sack_select_own_org ON public.sanction_acknowledgements;
CREATE POLICY sack_select_own_org
  ON public.sanction_acknowledgements FOR SELECT
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );
-- No INSERT/UPDATE/DELETE policy: writes only via M5 SECURITY DEFINER RPCs.

-- ── Data API Grants (INV-DATA-API-GRANT) ─────────────────────────────────────
GRANT SELECT ON TABLE public.sanction_acknowledgements TO authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.sanction_acknowledgements FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.sanction_acknowledgements FROM anon; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
GRANT ALL ON TABLE public.sanction_acknowledgements TO service_role;

-- ── 2. Widen chk_srq_status: add 'acknowledged' (H1 zero-downtime swap) ───────
-- ADD _v2 NOT VALID → VALIDATE → DROP old → RENAME back to canonical name, so a
-- valid constraint is enforced at all times and committed tests asserting the
-- canonical name keep passing.

ALTER TABLE public.sanction_review_queue
  ADD CONSTRAINT chk_srq_status_v2 CHECK (
    status IN ('pending', 'applied', 'rejected', 'disputed',
               'pending_peer_review', 'acknowledged')
  ) NOT VALID;
ALTER TABLE public.sanction_review_queue VALIDATE CONSTRAINT chk_srq_status_v2;
ALTER TABLE public.sanction_review_queue DROP CONSTRAINT IF EXISTS chk_srq_status; -- INV-DB: zero-downtime-verified (CHECK swap)
ALTER TABLE public.sanction_review_queue RENAME CONSTRAINT chk_srq_status_v2 TO chk_srq_status;

-- ── 3. Seal 'acknowledged' as TERMINAL in the srq immutability trigger ───────
-- Once a sanction is acknowledged the carrier has conceded the debt: no retract,
-- no re-dispute, no transition of any kind. Preserves all prior sealed fields.

CREATE OR REPLACE FUNCTION public.prevent_srq_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id   IS DISTINCT FROM OLD.organization_id   OR
     NEW.ledger_entry_id   IS DISTINCT FROM OLD.ledger_entry_id   OR
     NEW.set_id            IS DISTINCT FROM OLD.set_id            OR
     NEW.contract_id       IS DISTINCT FROM OLD.contract_id       OR
     NEW.verdict_evidence  IS DISTINCT FROM OLD.verdict_evidence  OR
     NEW.created_at        IS DISTINCT FROM OLD.created_at        OR
     NEW.vehicle_plate     IS DISTINCT FROM OLD.vehicle_plate     OR
     NEW.operator_name     IS DISTINCT FROM OLD.operator_name
  THEN
    RAISE EXCEPTION
      'sanction_review_queue: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- 'acknowledged' is a terminal status: the debt is conceded, no transition out.
  IF OLD.status = 'acknowledged' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION
      'sanction_review_queue: acknowledged is terminal — no transition (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

RESET client_min_messages;
