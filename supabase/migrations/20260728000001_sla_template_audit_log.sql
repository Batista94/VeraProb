-- pr_scanner: ignore-regression
-- Block 3 Meta-Audit: immutable SLA template change history.
-- INV-1  organization_id tenant isolation
-- INV-2  RLS via JWT app_metadata.org_id (never auth.uid())
-- INV-3  APPEND-ONLY — no UPDATE/DELETE (grant revoke + trigger guard)
-- INV-6  TIMESTAMPTZ mandatory
-- INV-DATA-API-GRANT  explicit Data API grants
-- INV-DB  non-destructive CREATE; columns NOT NULL on a fresh table

CREATE TABLE IF NOT EXISTS public.sla_template_audit_log (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL,
  template_id       UUID        NOT NULL,
  actor_session_id  TEXT        NOT NULL,
  action            TEXT        NOT NULL
    CHECK (action IN ('CREATED', 'UPDATED')),
  template_snapshot JSONB       NOT NULL,
  occurred_at_utc   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.sla_template_audit_log IS
  'Immutable change history of SLA templates for retroactive governance (INV-3).';

CREATE INDEX IF NOT EXISTS idx_sla_template_audit_log_lookup
  ON public.sla_template_audit_log (organization_id, template_id, occurred_at_utc DESC);

-- ── RLS (INV-1, INV-2) ─────────────────────────────────────────────────────
ALTER TABLE public.sla_template_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Read: sla_template_audit_log"
  ON public.sla_template_audit_log;
CREATE POLICY "Tenant Read: sla_template_audit_log"
  ON public.sla_template_audit_log FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

DROP POLICY IF EXISTS "Tenant Insert: sla_template_audit_log"
  ON public.sla_template_audit_log;
CREATE POLICY "Tenant Insert: sla_template_audit_log"
  ON public.sla_template_audit_log FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

-- ── Immutability guard (INV-3) ─────────────────────────────────────────────
-- Defense-in-depth: grants below already withhold UPDATE/DELETE from API roles;
-- this trigger raises loudly for any privileged path (owner/superuser) too,
-- so mutation attempts error (restrict_violation) instead of silently no-op.
CREATE OR REPLACE FUNCTION public.prevent_sla_template_audit_log_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'sla_template_audit_log is immutable (INV-3). Op: %, id: %',
    TG_OP, OLD.id USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_sla_template_audit_no_update
  ON public.sla_template_audit_log;
CREATE TRIGGER trg_sla_template_audit_no_update
  BEFORE UPDATE ON public.sla_template_audit_log
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sla_template_audit_log_mutation();

DROP TRIGGER IF EXISTS trg_sla_template_audit_no_delete
  ON public.sla_template_audit_log;
CREATE TRIGGER trg_sla_template_audit_no_delete
  BEFORE DELETE ON public.sla_template_audit_log
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sla_template_audit_log_mutation();

-- ── Data API grants (INV-DATA-API-GRANT) ───────────────────────────────────
-- Append-only: only SELECT + INSERT granted. No UPDATE/DELETE for any API role.
-- anon gets nothing: governance data is never reachable unauthenticated (INV-22).
REVOKE ALL ON TABLE public.sla_template_audit_log FROM anon;
REVOKE ALL ON TABLE public.sla_template_audit_log FROM authenticated;
REVOKE ALL ON TABLE public.sla_template_audit_log FROM service_role;
GRANT SELECT, INSERT ON TABLE public.sla_template_audit_log TO authenticated;
GRANT SELECT, INSERT ON TABLE public.sla_template_audit_log TO service_role;
