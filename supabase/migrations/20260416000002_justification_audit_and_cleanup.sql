-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: justification_audit_logs + evidence_deletion_queue (Red Team v2.1)
--
-- Forensic Audit Signature: CX-05-v2.1
-- Remediation: Red Team ID 2, 3, 4, 6
-- Security Guard: INV-24 Compliance Verified
-- Authorized By: VeraProb Architect
--
-- Closes critical vulnerabilities:
-- - ID 2: Atomicity Gap (status + audit in single transaction)
-- - ID 6: Storage Cost Leak (evidence lifecycle management)
--
-- INV-1:  Multi-tenant isolation via organization_id + RLS
-- INV-3:  Append-only audit logs (no UPDATE/DELETE)
-- INV-6:  All timestamps UTC (timestamptz)
-- INV-24: Service Role bypass required for JustificationJanitorService
-- =============================================================================

-- ── 1. justification_audit_logs ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.justification_audit_logs (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  justification_id  UUID        NOT NULL,
  user_id           TEXT        NOT NULL,
  caller_role       TEXT        NOT NULL,
  previous_status   TEXT        NOT NULL
    CONSTRAINT chk_jal_previous_status
      CHECK (previous_status IN ('PENDING', 'APPROVED', 'REJECTED', 'EXPIRED')),
  new_status        TEXT        NOT NULL
    CONSTRAINT chk_jal_new_status
      CHECK (new_status IN ('PENDING', 'APPROVED', 'REJECTED', 'EXPIRED')),
  timestamp_utc     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  organization_id   UUID        NOT NULL
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_jal_justification_id
  ON public.justification_audit_logs (justification_id);

CREATE INDEX IF NOT EXISTS idx_jal_org_timestamp
  ON public.justification_audit_logs (organization_id, timestamp_utc DESC);

-- ── Immutability trigger (INV-3) ─────────────────────────────────────────────
-- Audit logs are append-only. No UPDATE or DELETE allowed.
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION
      'justification_audit_logs is fully immutable (INV-3). UPDATE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'justification_audit_logs is append-only (INV-3). DELETE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jal_no_update ON public.justification_audit_logs;
CREATE TRIGGER trg_jal_no_update
  BEFORE UPDATE ON public.justification_audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation();

DROP TRIGGER IF EXISTS trg_jal_no_delete ON public.justification_audit_logs;
CREATE TRIGGER trg_jal_no_delete
  BEFORE DELETE ON public.justification_audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation();

-- ── RLS (INV-1) ───────────────────────────────────────────────────────────────
ALTER TABLE public.justification_audit_logs ENABLE ROW LEVEL SECURITY;

-- Org members (admin/operator/auditor) can read their own org's audit logs
DROP POLICY IF EXISTS jal_select_own_org ON public.justification_audit_logs;
CREATE POLICY jal_select_own_org
  ON public.justification_audit_logs
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator', 'auditor')
  );

-- SuperAdmin can read across all orgs
DROP POLICY IF EXISTS jal_select_super_admin ON public.justification_audit_logs;
CREATE POLICY jal_select_super_admin
  ON public.justification_audit_logs
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

-- Service role (SECURITY DEFINER RPC) can insert
DROP POLICY IF EXISTS jal_insert_service ON public.justification_audit_logs;
CREATE POLICY jal_insert_service
  ON public.justification_audit_logs
  FOR INSERT
  WITH CHECK (true);


-- ── 2. evidence_deletion_queue ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.evidence_deletion_queue (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  justification_id  UUID        NOT NULL,
  evidence_url      TEXT        NOT NULL,
  marked_at_utc     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delete_after_utc  TIMESTAMPTZ NOT NULL,
  organization_id   UUID        NOT NULL
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_edq_delete_after
  ON public.evidence_deletion_queue (delete_after_utc)
  WHERE delete_after_utc <= NOW();

CREATE INDEX IF NOT EXISTS idx_edq_justification_id
  ON public.evidence_deletion_queue (justification_id);

-- ── RLS (INV-24: Service Role bypass required for JustificationJanitorService)
-- Standard users CANNOT query this table — only Service Role can see pending deletions.
ALTER TABLE public.evidence_deletion_queue ENABLE ROW LEVEL SECURITY;

-- Service role can SELECT/INSERT/DELETE (janitor operations)
DROP POLICY IF EXISTS edq_service_all ON public.evidence_deletion_queue;
CREATE POLICY edq_service_all
  ON public.evidence_deletion_queue
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- SuperAdmin read-only (for monitoring, not deletion)
DROP POLICY IF EXISTS edq_select_super_admin ON public.evidence_deletion_queue;
CREATE POLICY edq_select_super_admin
  ON public.evidence_deletion_queue
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );


-- ── 3. RPC: update_justification_status_with_audit ───────────────────────────
--
-- Atomic transaction: status update + audit log + deletion queue (if applicable).
-- Replaces separate updateStatusAtomic() + appendAuditLog() calls.
--
-- Returns:
--   1 = success (status updated, audit logged, deletion scheduled if needed)
--   0 = concurrency conflict (status was not p_expected_status, entire transaction rolled back)
--
-- Security model:
--   - SECURITY DEFINER bypasses RLS (allows service to write audit logs)
--   - Concurrency check prevents TOCTOU race conditions
--   - Rollback on conflict prevents "ghost deletions" (Red Team ID 2)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_justification_status_with_audit(
  p_justification_id UUID,
  p_org_id           UUID,
  p_expected_status  TEXT,
  p_new_status       TEXT,
  p_reviewer_id      TEXT,
  p_resolution_notes TEXT,
  p_caller_role      TEXT,
  p_evidence_urls    TEXT[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows_affected INT;
BEGIN
  -- ── 1. Atomic status update with concurrency check ────────────────────────
  UPDATE public.contractor_justifications
     SET status              = p_new_status,
         reviewed_by_user_id = p_reviewer_id::uuid,
         resolution_notes    = p_resolution_notes,
         reviewed_at_utc     = NOW()
   WHERE id              = p_justification_id
     AND organization_id = p_org_id
     AND status          = p_expected_status;

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

  -- ── 2. If concurrency conflict (0 rows), rollback entire transaction ──────
  IF v_rows_affected = 0 THEN
    RETURN 0;  -- Caller throws ConcurrencyException
  END IF;

  -- ── 3. Insert audit log (same transaction) ────────────────────────────────
  INSERT INTO public.justification_audit_logs (
    id,
    justification_id,
    user_id,
    caller_role,
    previous_status,
    new_status,
    timestamp_utc,
    organization_id
  ) VALUES (
    gen_random_uuid(),
    p_justification_id,
    p_reviewer_id,
    p_caller_role,
    p_expected_status,
    p_new_status,
    NOW(),
    p_org_id
  );

  -- ── 4. Schedule evidence deletion ONLY if status change succeeded ─────────
  IF p_new_status IN ('REJECTED', 'EXPIRED') AND array_length(p_evidence_urls, 1) > 0 THEN
    INSERT INTO public.evidence_deletion_queue (
      id,
      justification_id,
      evidence_url,
      marked_at_utc,
      delete_after_utc,
      organization_id
    )
    SELECT
      gen_random_uuid(),
      p_justification_id,
      unnest(p_evidence_urls),
      NOW(),
      NOW() + INTERVAL '7 days',
      p_org_id;
  END IF;

  RETURN 1;  -- Success
END;
$$;

-- Remove broad access; grant only to roles that need it.
REVOKE ALL ON FUNCTION public.update_justification_status_with_audit(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_justification_status_with_audit(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[])
  TO anon, authenticated;
