-- =============================================================================
-- Migration: Phase 10.8 — SLA Sandbox Schema (ROI Simulator)
--
-- Creates the Shadow Ledger: sandbox_simulation_sessions +
-- sandbox_simulation_results. Ephemeral computational branch that reads
-- from the immutable production ledger and stores what-if outcomes.
--
-- INV-1:  organization_id on every row + RLS.
-- INV-2:  RLS via auth.jwt() -> 'app_metadata' ->> 'org_id'.
-- INV-3:  Append-only during TTL (no UPDATE/DELETE by authenticated).
--         GC worker (service_role) deletes after expires_at_utc.
-- INV-4:  All monetary values BIGINT cents.
-- INV-5:  delta_bps INT (basis points).
-- INV-6:  TIMESTAMPTZ mandatory.
-- INV-22: Tenant isolation via RLS + Red-Team tested.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. sandbox_simulation_sessions ──────────────────────────────────────────
-- Master record for each simulation run.
-- One session = one "What-If" question asked by a Tenant Admin.

CREATE TABLE IF NOT EXISTS public.sandbox_simulation_sessions (
  id                            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id               UUID        NOT NULL,             -- INV-1
  contract_id                   UUID        NOT NULL,             -- target contract
  session_label                 TEXT        NOT NULL,             -- user-provided name
  period_start_utc              TIMESTAMPTZ NOT NULL,             -- INV-6
  period_end_utc                TIMESTAMPTZ NOT NULL,             -- INV-6
  overrides_snapshot            JSONB       NOT NULL,             -- full override payload (sealed)

  -- Aggregate results (computed at session close)
  baseline_total_fines_cents    BIGINT      NOT NULL DEFAULT 0,   -- INV-4
  simulated_total_fines_cents   BIGINT      NOT NULL DEFAULT 0,   -- INV-4
  delta_cents                   BIGINT      NOT NULL DEFAULT 0,   -- INV-4: positive = savings
  delta_bps                     INT,                              -- INV-5: basis points
  baseline_event_count          INT         NOT NULL DEFAULT 0,
  simulated_capped_event_count  INT         NOT NULL DEFAULT 0,

  -- Provenance
  created_by_user_id            UUID        NOT NULL,
  created_at_utc                TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- INV-6
  expires_at_utc                TIMESTAMPTZ NOT NULL,             -- GC eligibility (30d)

  CONSTRAINT chk_sandbox_period CHECK (period_end_utc > period_start_utc),
  CONSTRAINT chk_sandbox_expiry CHECK (expires_at_utc > created_at_utc),
  CONSTRAINT chk_sandbox_max_period CHECK (
    period_end_utc <= period_start_utc + INTERVAL '6 months'
  )
);

COMMENT ON TABLE public.sandbox_simulation_sessions IS
  'SLA Sandbox: master record per What-If simulation. Ephemeral (30d TTL). '
  'INV-1/2/3/4/5/6/22. Phase 10.8.';

-- ── 2. sandbox_simulation_results ───────────────────────────────────────────
-- Per-event detail: one row per original penal ledger entry, re-evaluated.

CREATE TABLE IF NOT EXISTS public.sandbox_simulation_results (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id              UUID        NOT NULL
    REFERENCES public.sandbox_simulation_sessions(id) ON DELETE CASCADE,
  organization_id         UUID        NOT NULL,           -- INV-1 (denormalized for RLS)
  source_ledger_entry_id  UUID        NOT NULL,           -- bare UUID, NOT an FK (design §3.2)
  source_event_type       TEXT        NOT NULL,           -- original ledger event type
  occurred_at_utc         TIMESTAMPTZ NOT NULL,           -- INV-6: original event time

  -- Baseline (production reality)
  baseline_fine_cents     BIGINT      NOT NULL,           -- INV-4
  baseline_rule_snapshot  JSONB       NOT NULL,           -- rule_config at time of verdict

  -- Simulated (hypothetical)
  simulated_fine_cents    BIGINT      NOT NULL,           -- INV-4
  simulated_rule_applied  JSONB       NOT NULL,           -- override or fallthrough config
  was_override_applied    BOOLEAN     NOT NULL,           -- true if override changed the outcome

  -- Financial Guard simulation
  baseline_cap_truncated  BOOLEAN     NOT NULL DEFAULT FALSE,
  simulated_cap_truncated BOOLEAN     NOT NULL DEFAULT FALSE,

  created_at_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.sandbox_simulation_results IS
  'SLA Sandbox: per-event A/B comparison detail. Cascade-deleted with session. '
  'INV-1/4/6. Phase 10.8.';

-- ── 3. Immutability (authenticated cannot UPDATE or DELETE) ─────────────────
-- Sessions: append-only during TTL. Only service_role GC deletes after expiry.
-- Results: cascade-deleted via FK when session is GC'd.

CREATE OR REPLACE FUNCTION public.prevent_sandbox_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'sandbox tables are append-only during TTL (INV-3). '
    'Only the GC worker (service_role) may delete expired sessions.'
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- Sessions: block UPDATE + DELETE
CREATE TRIGGER trg_sandbox_sessions_no_update
  BEFORE UPDATE ON public.sandbox_simulation_sessions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sandbox_mutation();

CREATE TRIGGER trg_sandbox_sessions_no_delete
  BEFORE DELETE ON public.sandbox_simulation_sessions
  FOR EACH ROW
  WHEN (current_setting('app.gc_sandbox', true) IS DISTINCT FROM 'true')
  EXECUTE FUNCTION public.prevent_sandbox_mutation();

-- Results: block UPDATE + DELETE
CREATE TRIGGER trg_sandbox_results_no_update
  BEFORE UPDATE ON public.sandbox_simulation_results
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sandbox_mutation();

CREATE TRIGGER trg_sandbox_results_no_delete
  BEFORE DELETE ON public.sandbox_simulation_results
  FOR EACH ROW
  WHEN (current_setting('app.gc_sandbox', true) IS DISTINCT FROM 'true')
  EXECUTE FUNCTION public.prevent_sandbox_mutation();

-- ── 4. Indexes ──────────────────────────────────────────────────────────────

-- Session queries: "my simulations, newest first"
CREATE INDEX idx_sandbox_sessions_org_date
  ON public.sandbox_simulation_sessions (organization_id, created_at_utc DESC);

-- GC eligibility scan
CREATE INDEX idx_sandbox_sessions_expiry
  ON public.sandbox_simulation_sessions (expires_at_utc)
  WHERE expires_at_utc IS NOT NULL;

-- Result detail: "all results for this session"
CREATE INDEX idx_sandbox_results_session
  ON public.sandbox_simulation_results (session_id, occurred_at_utc);

-- RLS acceleration
CREATE INDEX idx_sandbox_results_org
  ON public.sandbox_simulation_results (organization_id);

-- ── 5. Row Level Security ───────────────────────────────────────────────────

ALTER TABLE public.sandbox_simulation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sandbox_simulation_results  ENABLE ROW LEVEL SECURITY;

-- Sessions: org isolation (INV-2)
CREATE POLICY sandbox_sessions_org_isolation
  ON public.sandbox_simulation_sessions
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY sandbox_sessions_insert_org
  ON public.sandbox_simulation_sessions
  FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- SuperAdmin cross-tenant read-only
CREATE POLICY sandbox_sessions_superadmin_read
  ON public.sandbox_simulation_sessions
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE);

-- Results: org isolation (INV-2)
CREATE POLICY sandbox_results_org_isolation
  ON public.sandbox_simulation_results
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY sandbox_results_insert_org
  ON public.sandbox_simulation_results
  FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- SuperAdmin cross-tenant read-only
CREATE POLICY sandbox_results_superadmin_read
  ON public.sandbox_simulation_results
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE);

-- ── 6. Explicit API grants (INV-DATA-API-GRANT) ────────────────────────────

GRANT SELECT, INSERT ON public.sandbox_simulation_sessions TO authenticated;
GRANT SELECT, INSERT ON public.sandbox_simulation_results  TO authenticated;

GRANT ALL ON public.sandbox_simulation_sessions TO service_role;
GRANT ALL ON public.sandbox_simulation_results  TO service_role;

-- Block UPDATE/DELETE from authenticated (defense-in-depth: triggers + grants)
REVOKE UPDATE, DELETE ON public.sandbox_simulation_sessions FROM authenticated;
REVOKE UPDATE, DELETE ON public.sandbox_simulation_results  FROM authenticated;
