-- Suppress DROP TRIGGER IF EXISTS NOTICEs (triggers don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Phase 9.2 — Tenant Billing Events (INV-1: Append-Only)
-- =============================================================================
-- Records every plan/limit change made by SuperAdmin for forensic traceability.
-- Append-only enforced via BEFORE UPDATE/DELETE triggers (pattern from 20260404120000).
-- =============================================================================


-- =============================================================================
-- A. tenant_billing_events TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.tenant_billing_events (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         UUID        REFERENCES public.organizations(id),
  event_type              TEXT        NOT NULL,
  old_plan                TEXT,
  new_plan                TEXT,
  changed_by_super_admin_id UUID,
  reason                  TEXT,
  occurred_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  old_max_vehicles        INT,
  new_max_vehicles        INT,
  old_max_contracts       INT,
  new_max_contracts       INT
);

-- Immutability triggers (INV-1 — same pattern as 20260404120000).
CREATE OR REPLACE FUNCTION public.prevent_billing_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'tenant_billing_events is immutable (INV-1). Operation: %, id: %',
    TG_OP,
    OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_billing_events_no_update ON public.tenant_billing_events;
CREATE TRIGGER trg_billing_events_no_update
  BEFORE UPDATE ON public.tenant_billing_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_billing_event_mutation();

DROP TRIGGER IF EXISTS trg_billing_events_no_delete ON public.tenant_billing_events;
CREATE TRIGGER trg_billing_events_no_delete
  BEFORE DELETE ON public.tenant_billing_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_billing_event_mutation();

-- RLS: deny by default for authenticated (SuperAdmin reads via service_role which bypasses RLS).
ALTER TABLE public.tenant_billing_events ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- B. organizations — partial unique index on CNPJ (R2 mitigation)
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_cnpj
  ON public.organizations(cnpj)
  WHERE cnpj IS NOT NULL;


-- =============================================================================
-- C. Performance indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_billing_events_org_time
  ON public.tenant_billing_events(organization_id, occurred_at_utc DESC);
