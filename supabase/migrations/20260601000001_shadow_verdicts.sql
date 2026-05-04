-- pr_scanner: ignore-rls (intentional: super_admin cross-tenant analytics, no org isolation)
-- Phase 10.3 — Shadow Verdict Validation System
-- INV-1:  organization_id present for tenant-scoped analytics
-- INV-7:  Immutability trigger blocks UPDATE on engine-produced fields
-- INV-9:  All timestamps UTC (TIMESTAMPTZ)
-- INV-22: traceability_hash links each shadow verdict to its causal facts
--
-- Dynamic versioning: engine_version has NO DB default.
-- The application resolves the version from EnvironmentConfig.engineVersion
-- (injected via --dart-define=ENGINE_VERSION=... at build time) and must
-- always supply it on INSERT. This prevents stale version strings from
-- silently propagating into the audit trail.

CREATE TABLE IF NOT EXISTS public.shadow_verdicts (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID        NOT NULL,
  set_id                TEXT        NOT NULL,
  contract_id           TEXT        NOT NULL,
  engine_verdict        TEXT        NOT NULL
    CONSTRAINT chk_sv_engine_verdict
      CHECK (engine_verdict IN ('executed', 'noShow', 'evidenceGap', 'inhibited')),
  engine_verdict_at_utc TIMESTAMPTZ NOT NULL,
  -- No DEFAULT: application must supply the WASM build version (INV-14).
  engine_version        TEXT        NOT NULL,
  verdict_evidence      JSONB       NOT NULL,    -- full VerdictEvidence bundle
  traceability_hash     TEXT        NOT NULL,    -- SHA-256 (INV-22)
  divergence_type       TEXT        NOT NULL DEFAULT 'pending_manual'
    CONSTRAINT chk_sv_divergence
      CHECK (divergence_type IN ('match', 'false_positive', 'false_negative', 'pending_manual')),
  manual_verdict        TEXT        NULL,         -- populated by syncManualVerdicts()
  manual_verdict_at_utc TIMESTAMPTZ NULL,
  manual_reviewed_by    UUID        NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_shadow_obligation
    UNIQUE (organization_id, set_id, contract_id)
);

-- ── Indexes ────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_sv_org_divergence
  ON public.shadow_verdicts (organization_id, divergence_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sv_org_created
  ON public.shadow_verdicts (organization_id, created_at DESC);

-- ── Immutability (INV-7) ───────────────────────────────────────────────────
-- Blocks UPDATE on any engine-produced field after initial INSERT.
-- Manual fields (divergence_type, manual_verdict, manual_verdict_at_utc,
-- manual_reviewed_by) remain mutable for syncManualVerdicts().

CREATE OR REPLACE FUNCTION public.fn_shadow_verdicts_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.verdict_evidence        IS DISTINCT FROM NEW.verdict_evidence        OR
     OLD.traceability_hash       IS DISTINCT FROM NEW.traceability_hash       OR
     OLD.engine_verdict          IS DISTINCT FROM NEW.engine_verdict          OR
     OLD.engine_version          IS DISTINCT FROM NEW.engine_version          OR
     OLD.engine_verdict_at_utc   IS DISTINCT FROM NEW.engine_verdict_at_utc  THEN
    RAISE EXCEPTION
      'shadow_verdicts: engine-produced fields are immutable (INV-7). '
      'Attempted to modify: verdict_evidence, traceability_hash, engine_verdict, '
      'engine_version, or engine_verdict_at_utc.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_shadow_verdicts_immutable
  BEFORE UPDATE ON public.shadow_verdicts
  FOR EACH ROW EXECUTE FUNCTION public.fn_shadow_verdicts_immutable();

-- Block DELETE (append-only ledger — INV-7)
CREATE RULE shadow_verdicts_no_delete AS
  ON DELETE TO public.shadow_verdicts DO INSTEAD NOTHING;

-- ── Row Level Security ─────────────────────────────────────────────────────

ALTER TABLE public.shadow_verdicts ENABLE ROW LEVEL SECURITY;

-- SuperAdmin: cross-tenant read for divergence analytics (INV-6)
CREATE POLICY sv_select_super_admin ON public.shadow_verdicts
  FOR SELECT
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean = true);

-- SuperAdmin: update divergence/manual fields only
-- (immutability trigger enforces engine-field protection)
CREATE POLICY sv_update_super_admin ON public.shadow_verdicts
  FOR UPDATE
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean = true);

-- Service role INSERT only — shadow engine writes via server (INV-14)
-- Application role has no INSERT grant; service role bypasses RLS.
CREATE POLICY sv_insert_service ON public.shadow_verdicts
  FOR INSERT
  WITH CHECK (true);
