-- =============================================================================
-- Phase 9.2 — system_audit_log: add organization_id for per-tenant filtering
-- =============================================================================
-- Adds nullable organization_id FK so SuperAdmin can filter system events by tenant.
-- Existing PG RULES (no_update, no_delete) are DDL-immune — they remain active.
-- =============================================================================

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id);

-- Partial index: only index rows that belong to a specific org (most rows are global).
CREATE INDEX IF NOT EXISTS idx_system_audit_log_org_time
  ON public.system_audit_log(organization_id, occurred_at DESC)
  WHERE organization_id IS NOT NULL;
