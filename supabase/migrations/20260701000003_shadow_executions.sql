-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Shadow Executions (Ad-hoc Cost Capture)
--
-- Captures unlinked evidence events as traceable cost objects.
-- When no planned/inTransit execution is found for a Telegram evidence upload,
-- instead of losing the event as a pure orphan, a shadow_execution row is
-- created. Supervisors reconcile these in the Command Center.
--
-- Bounded Context: domain/ad_hoc_cost (INV-14: not the FSM execution domain)
-- INV-1:  organization_id on all rows + RLS.
-- INV-3:  Separate append-only transition log. Shadow row itself is mutable
--         (status transitions UNLINKED_SHADOW → RECONCILED/DISMISSED) but
--         guarded by immutability trigger (no timestamp re-stamping, no regression).
-- INV-14: operator_id (not driver_id) + origin_channel for channel-agnostic future.
-- INV-22: UNIQUE(origin_evidence_id) — cross-org collision impossible.
-- INV-26: create_shadow_execution RPC returns no_data_found for wrong-org (anti-oracle).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. shadow_executions table ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.shadow_executions (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         UUID        NOT NULL,                    -- INV-1
  operator_id             UUID        NOT NULL,                    -- INV-14: transport-agnostic
  chat_id                 BIGINT      NOT NULL,
  telegram_message_id     BIGINT      NOT NULL,                    -- forensic chain anchor
  origin_evidence_id      UUID        NOT NULL
    REFERENCES public.telegram_evidence_uploads(id),
  origin_channel          TEXT        NOT NULL DEFAULT 'telegram', -- INV-14: WhatsApp/app ready
  message_ts              BIGINT      NOT NULL,                    -- device clock anchor (INV-6)
  counted_from_utc        TIMESTAMPTZ NOT NULL DEFAULT NOW(),      -- DB-set trusted time anchor
  status                  TEXT        NOT NULL DEFAULT 'UNLINKED_SHADOW'
    CONSTRAINT chk_se_status CHECK (
      status IN ('UNLINKED_SHADOW', 'RECONCILED', 'RECONCILED_AS_NEW_REVENUE', 'DISMISSED')
    ),
  -- RECONCILED_AS_NEW_REVENUE: no matching planned execution → ad-hoc billing row created
  reconciled_execution_id TEXT,                                    -- set_id of target execution
  reconciled_at_utc       TIMESTAMPTZ,                             -- NULL → timestamp once
  reconciled_by_user_id   UUID,
  dismissed_at_utc        TIMESTAMPTZ,                             -- NULL → timestamp once
  dismissed_by_user_id    UUID,
  dismissed_reason        TEXT,
  created_at_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Idempotency: one shadow per evidence (INV-22 — includes org_id via evidence FK)
  CONSTRAINT uq_se_evidence UNIQUE (origin_evidence_id)
);

CREATE INDEX IF NOT EXISTS idx_se_org_status
  ON public.shadow_executions (organization_id, status, created_at_utc DESC);

CREATE INDEX IF NOT EXISTS idx_se_operator
  ON public.shadow_executions (operator_id, organization_id);

-- ── 2. Immutability trigger ───────────────────────────────────────────────────
-- Guards NULL-once timestamps and blocks status regression.
-- RECONCILED and DISMISSED are terminal states.

CREATE OR REPLACE FUNCTION public.guard_shadow_execution_transitions()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.reconciled_at_utc IS NOT NULL AND NEW.reconciled_at_utc IS NULL THEN
    RAISE EXCEPTION 'shadow_executions: reconciled_at_utc is immutable (INV-3)'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.dismissed_at_utc IS NOT NULL AND NEW.dismissed_at_utc IS NULL THEN
    RAISE EXCEPTION 'shadow_executions: dismissed_at_utc is immutable (INV-3)'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.status IN ('RECONCILED', 'RECONCILED_AS_NEW_REVENUE', 'DISMISSED') THEN
    RAISE EXCEPTION 'shadow_executions: terminal status % cannot transition (INV-3)', OLD.status
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_shadow_transitions ON public.shadow_executions;
CREATE TRIGGER trg_guard_shadow_transitions
  BEFORE UPDATE ON public.shadow_executions
  FOR EACH ROW EXECUTE FUNCTION public.guard_shadow_execution_transitions();

DROP TRIGGER IF EXISTS trg_se_no_delete ON public.shadow_executions;
CREATE TRIGGER trg_se_no_delete
  BEFORE DELETE ON public.shadow_executions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();

-- ── 3. shadow_execution_transitions (append-only audit log, INV-3) ───────────

CREATE TABLE IF NOT EXISTS public.shadow_execution_transitions (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  shadow_id        UUID        NOT NULL REFERENCES public.shadow_executions(id),
  organization_id  UUID        NOT NULL,                           -- INV-1
  from_status      TEXT        NOT NULL,
  to_status        TEXT        NOT NULL,
  transitioned_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  transitioned_by  UUID,
  reason           TEXT
);

CREATE INDEX IF NOT EXISTS idx_set_shadow_id
  ON public.shadow_execution_transitions (shadow_id, transitioned_at DESC);

DROP TRIGGER IF EXISTS trg_set_no_update ON public.shadow_execution_transitions;
CREATE TRIGGER trg_set_no_update
  BEFORE UPDATE ON public.shadow_execution_transitions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();

DROP TRIGGER IF EXISTS trg_set_no_delete ON public.shadow_execution_transitions;
CREATE TRIGGER trg_set_no_delete
  BEFORE DELETE ON public.shadow_execution_transitions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();

-- ── 3b. Auto-log transitions (INV-3, INV-21) ─────────────────────────────────
-- Trigger fires AFTER UPDATE on shadow_executions to auto-insert a transition
-- row. This makes it impossible for the application layer to skip the audit log.

CREATE OR REPLACE FUNCTION public.auto_log_shadow_transition()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO shadow_execution_transitions (
      shadow_id, organization_id, from_status, to_status,
      transitioned_by, reason
    ) VALUES (
      NEW.id, NEW.organization_id, OLD.status, NEW.status,
      COALESCE(NEW.reconciled_by_user_id, NEW.dismissed_by_user_id),
      NEW.dismissed_reason
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_log_shadow_transition ON public.shadow_executions;
CREATE TRIGGER trg_auto_log_shadow_transition
  AFTER UPDATE ON public.shadow_executions
  FOR EACH ROW EXECUTE FUNCTION public.auto_log_shadow_transition();

-- ── 4. RLS ────────────────────────────────────────────────────────────────────
-- Uses app_metadata path (post-20260317000001_rls_jwt_path_unification convention).
-- SELECT: OPERATOR (OCC triage), AUDITOR (financial audit), TENANT_ADMIN.
-- INSERT/UPDATE: service_role only (webhook + reconciliation RPC).
-- DELETE: blocked by trigger above.

ALTER TABLE public.shadow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shadow_execution_transitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS se_select_org ON public.shadow_executions;
CREATE POLICY se_select_org ON public.shadow_executions
  FOR SELECT USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

DROP POLICY IF EXISTS se_select_super_admin ON public.shadow_executions;
CREATE POLICY se_select_super_admin ON public.shadow_executions
  FOR SELECT USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

-- INSERT: service_role only (webhook + reconciliation RPC). service_role bypasses RLS by design.
-- No INSERT policy needed — absence of policy = deny for authenticated users (INV-22).

DROP POLICY IF EXISTS se_insert_service ON public.shadow_executions;

DROP POLICY IF EXISTS se_update_service ON public.shadow_executions;
CREATE POLICY se_update_service ON public.shadow_executions
  FOR UPDATE USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR')
  );

DROP POLICY IF EXISTS set_select_org ON public.shadow_execution_transitions;
CREATE POLICY set_select_org ON public.shadow_execution_transitions
  FOR SELECT USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- INSERT: service_role only. No INSERT policy = deny for authenticated (INV-22).
DROP POLICY IF EXISTS set_insert_service ON public.shadow_execution_transitions;

-- ── 5. create_shadow_execution RPC ───────────────────────────────────────────
-- INV-1/INV-26: Verifies evidence belongs to org before inserting.
--               Wrong-org raises no_data_found (same shape as not-found, anti-oracle).
-- Idempotent: ON CONFLICT (origin_evidence_id) returns existing shadow UUID.
-- SECURITY DEFINER + SET search_path: webhook runs as service_role, not tenant.

CREATE OR REPLACE FUNCTION public.create_shadow_execution(
  p_org_id              UUID,
  p_operator_id         UUID,
  p_chat_id             BIGINT,
  p_evidence_id         UUID,
  p_telegram_message_id BIGINT,
  p_message_ts          BIGINT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_shadow_id  UUID;
  v_caller_org UUID;
BEGIN
  -- INV-1 Fail-Fast: reject if authenticated caller's JWT org doesn't match p_org_id.
  -- service_role callers have no app_metadata → v_caller_org is NULL → bypassed (webhook path).
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  IF v_caller_org IS NOT NULL AND v_caller_org <> p_org_id THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'no_data_found';
  END IF;

  -- INV-26: evidence must belong to the supplied org.
  -- Wrong-org returns same error as not-found (anti-oracle — both return identical response).
  IF NOT EXISTS (
    SELECT 1 FROM telegram_evidence_uploads
    WHERE id = p_evidence_id AND organization_id = p_org_id
  ) THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO shadow_executions (
    organization_id,
    operator_id,
    chat_id,
    telegram_message_id,
    origin_evidence_id,
    message_ts
  ) VALUES (
    p_org_id,
    p_operator_id,
    p_chat_id,
    p_telegram_message_id,
    p_evidence_id,
    p_message_ts
  )
  ON CONFLICT (origin_evidence_id) DO UPDATE
    SET id = shadow_executions.id   -- no-op, first-wins idempotency
  RETURNING id INTO v_shadow_id;

  RETURN v_shadow_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_shadow_execution(UUID, UUID, BIGINT, UUID, BIGINT, BIGINT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_shadow_execution(UUID, UUID, BIGINT, UUID, BIGINT, BIGINT)
  TO authenticated;
